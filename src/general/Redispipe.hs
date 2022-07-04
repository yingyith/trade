{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE NamedFieldPuns,RecordWildCards #-}
module Redispipe
    ( publishThread,
      onInitialComplete,
      handlerThread,
      opclHandler,
      listenkeyHandler,
      mintocacheHandler,
      showChannels,
      depthtoredis,
      sndtocacheHandler,
      detailanalysHandler,
      detailopHandler,
      detailpubHandler,
      analysisHandler

    ) where
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`

import Database.Redis as R
import Data.Monoid ((<>))
import Data.Time
import GHC.Generics
import GHC.Conc
--import GHC.Records(getField)
import Control.Monad
import Control.Exception as CE
import Control.Monad.Loops
import Control.Monad.Trans (liftIO)
import Control.Concurrent
import Control.Lens
import Network.WebSockets as NW --(ClientApp, receiveData, sendClose, sendTextData,send,WebSocketsData)
import Network.WebSockets (sendPong)
import Network.WebSockets.Connection as NC
import Control.Concurrent.Async as CA
import Control.Concurrent.STM
import Control.Concurrent.STM.TBQueue
import Control.Concurrent 
import Data.Text as T
import Data.Text.IO as T
import Data.ByteString as DB
import Data.Text.Encoding
import System.IO as SI
import Data.Aeson as A
import Data.Aeson.Lens as DAL
import qualified Data.HashMap  as DHM
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.List.Split as DLT
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.UTF8 as BLU
import qualified Data.ByteString.Lazy as BL
import Data.Aeson.Types as DAT
import Data.List as DL
import Data.Maybe
import Data.Either
import Httpstructure
import Type.Reflection
import Lib
import Rediscache
import Globalvar
import Order
import Myutils
import Logger
import System.Log.Logger 
import System.Log.Handler (setFormatter)
import System.Log.Handler.Syslog
import System.Log.Handler.Simple
import System.Log.Formatter
import Events
import Colog (LogAction,logByteStringStdout)
import Redisutils
import qualified Analysistructure as Anlys
import Mobject


replydo :: Integer -> Redis (Either Reply [ByteString], Either Reply [ByteString])
replydo timeint = do
        let akey = BLU.fromString threemkey
        item <- zrange akey 0 1
        let timevalue = BLU.fromString $  show timeint
        let timekeyy = BLU.fromString timekey
        void $ R.set timekeyy timevalue
        orderitem <- getorderfromredis
        let reitem = (item,orderitem)
        return  reitem 
        

            
iscacheinvalid    ::         Bool  
iscacheinvalid = True
ispinginvalid     ::         Bool  
ispinginvalid = True
isstrategyinvalid ::         Bool  
isstrategyinvalid = True

msgcacheandpingtempdo :: ByteString -> Redis ()
msgcacheandpingtempdo msg  = do
    liftIO $ logact logByteStringStdout "befcache--loopupd -----------!"                             
    void $ publish "minc:1" ("cache" <> msg)
    void $ publish "listenkey:1" ("listenkey" <> msg)


sendpongdo :: NC.Connection -> IO ()
sendpongdo conn = do
    sendPong conn (T.pack $ show "")
    sendPing conn (T.pack $ show "")
    sendPong conn (T.pack $ show "")
          

matchmsgfun :: ByteString -> IO String
matchmsgfun msg = do
    let  matchkline = DB.drop 11 $ DB.take 24 msg 
    let  matchkmsg = BLU.fromString "adausdt@kline"
    let  matchdepth = DB.drop 11 $ DB.take 30 msg 
    let  matchdmsg = BLU.fromString "adausdt@depth@500ms"
    let  matchacevent = DB.drop 90 $ DB.take 103 msg 
    let  matchacmsg = BLU.fromString "ACCOUNT_UPDATE"
    let  matchorevent = DB.drop 90 $ DB.take 108 msg 
    let  matchormsg = BLU.fromString "ORDER_TRADE_UPDATE"
    --liftIO $ logact logByteStringStdout $ B.pack $  show (matchacevent,matchorevent)                         
    let klinepredi = matchkline == matchkmsg
    let depthpredi = matchdepth == matchdmsg
    let acpredi = matchacevent == matchacmsg
    let orpredi = matchorevent == matchormsg
    case (klinepredi,depthpredi,acpredi,orpredi) of 
        (True  ,_      ,_     ,_     ) -> return "kline"
        (_     ,True   ,_     ,_     ) -> return "depth"
        (_     ,_      ,True  ,_     ) -> return "ac"
        (_     ,_      ,_     ,True  ) -> return "or"
        (_     ,_      ,_     ,_     ) -> return "no"


msgordertempdo :: ByteString -> ByteString -> Redis ()
msgordertempdo msg osdetail =  do
    let orderorigin = BLU.toString osdetail
    let order = DLT.splitOn "|" orderorigin 
    let orderstate = DL.last order
    let orderquan =  read $ order!!4 :: Integer
    let seperate = BLU.fromString ":::"
    let mmsg = osdetail <> seperate <> msg

    when (DL.any (== orderstate) [(show $ fromEnum Cprepare),(show $ fromEnum Ccancel),(show $ fromEnum Cprocess),(show $ fromEnum Cpartdone),(show $ fromEnum Cproinit),
                                  (show $ fromEnum Prepare),(show $ fromEnum Process),(show $ fromEnum Ppartdone),(show $ fromEnum Proinit),(show $ fromEnum HalfDone)
                                 ]  )  $ do 
        liftIO $ logact logByteStringStdout "take order part"                             
        void $ publish "order:1" ("order" <> mmsg )
    

--msgsklinetoredis :: ByteString -> Integer -> Redis ()
--msgsklinetoredis msg stamp = do
--      void $ publish "sndc:1" ( msg)
--      let abyvaluestr = msg
--      let abykeystr = BLU.fromString secondkey
--      let stamptime = fromInteger stamp :: Double
--      void $ zadd abykeystr [(-stamptime,abyvaluestr)]
--      void $ zremrangebyrank abykeystr 150 1000


depthtoredis :: [(Double,BLU.ByteString)] -> String -> Redis ()
depthtoredis iteml side = do
      let abykeystr = BLU.fromString $ case side of 
                                           "bids" -> biddepth 
                                           "asks" -> askdepth 
      void $ zadd abykeystr iteml

msgklinedoredis :: Integer -> ByteString  ->  Redis ()
msgklinedoredis curtimestamp msg = do 
      res <- replydo curtimestamp 
      let klineitem = fst res
      let orderitem = snd res
      --liftIO $ logact logByteStringStdout $ B.pack $ show ("index too large --------!",klineitem)
      let cachetime = case klineitem of
            Left _  ->  "some error"
            Right v ->   (v!!0)
      let orderdet  = case orderitem of
            Left _  ->  "some error"
            Right v ->   (v!!0)
      void $ publish "sndc:1" ( msg)
      msgordertempdo msg orderdet
      let replydomarray = DLT.splitOn "|" $ BLU.toString cachetime
      let replydores = (read (replydomarray !! 0)) :: Integer
      let timediffi = curtimestamp-replydores
      --msgsklinetoredis msg curtimestamp
      void $ publish "analysis:1" ( msg)
      return ()
      
      

getliskeyfromredis :: Redis ()
getliskeyfromredis =  return ()

publishThread :: TBQueue Cronevent ->  R.Connection -> NC.Connection -> IO (TVar a) -> ThreadId -> IO ()
publishThread tbq rc wc tvar ptid = do 
    iterateM_  ( \(timecountb,intervalcb) -> do
         message <- (NC.receiveData wc)
         --logact logByteStringStdout $ message                              
         curtimestamp <- round . (* 1000) <$> getPOSIXTime
         let timecounta   = (curtimestamp `quot` 60000) 
         let timecountpred = (timecounta - timecountb) >= 1 
         let intervalcbpred = intervalcb == 0
         matchoevt  <- matchmsgfun message
         returnres  <-  case (timecountpred,intervalcbpred) of 
              (True ,True )   -> do
                                     sendpongdo wc
                                     let aevent = Cronevent "cachep"  (Just message) Nothing
                                     addoeventtotbqueue aevent tbq
                                     return (timecounta,intervalcb+1)                                  -- update timecounta  intervalcount +1
              (True ,False)   -> do  
                                     return (timecounta,intervalcb+1)                                  --no update timecounta     intervalcount+1
              (False,True )   -> do  
                                     return (timecountb,0)
              (False,False)   -> do 
                                     return (timecountb,0)--reset intercalcount



         when (matchoevt == "kline") $ do
              let aevent = Cronevent "kline"  (Just message) Nothing
              addoeventtotbqueue aevent tbq


         when (matchoevt == "or" || matchoevt == "ac" || matchoevt == "no") $ do
              let aevent = Cronevent "other"  (Just message) Nothing
              addoeventtotbqueue aevent tbq

         when (matchoevt == "depth") $ do
              let aevent = Cronevent "depth"  (Just message) Nothing
              addoeventtotbqueue aevent tbq

         return returnres 
      )  (0,0)
      
detailpubHandler :: TBQueue Cronevent  -> R.Connection -> IO () 
detailpubHandler tbq conn = do 
    iterateM_  ( \(lastetype,forbidtime) -> do 
        res      <- atomically $ readTBQueue tbq
        tbqlen   <- atomically $ lengthTBQueue tbq
        currtimee <- getcurtimestamp 
        let currtime = toInteger currtimee
        let curtime = fromIntegral currtime ::Double
        let et      = ectype res
        let etcont  = fromJust (eccont res)

        when (et == "kline")   $  do 
           runRedis conn (msgklinedoredis currtime etcont )

        when (et == "depth")   $  do 
           runRedis conn $ do 
               void $ publish "depth:1" ( etcont)

        when (et == "other")   $  do 
           logact logByteStringStdout $ B.pack $ show ("dopubb len is !",tbqlen,et,etcont)
           runRedis conn $ do 
               res <- replydo currtime
               let orderitem = snd res
               let orderdet  = case orderitem of
                     Left _  ->  "some error"
                     Right v ->   (v!!0)
               msgordertempdo etcont orderdet

        when (et == "cachep")   $  do 
           runRedis conn (msgcacheandpingtempdo  etcont )
        return (0,0) )  (0,0)


onInitialComplete :: IO ()
onInitialComplete = SI.hPutStrLn stderr "Initial subscr complete"

debugtime :: IO ()
debugtime = do 
    currtime <- getcurtimestamp 
    let curtime = fromIntegral currtime ::Double
    return ()

handlerThread :: R.Connection -> PubSubController -> IO (TVar a) -> IO ()
handlerThread conn ctrl tvar = do 
    forever $
       pubSubForever conn ctrl onInitialComplete
         `catch` (\(e :: SomeException) -> do
           SI.hPutStrLn stderr $ "Got error: " ++ show e
           )


detailopHandler :: TBQueue Opevent  -> R.Connection -> IO () 
detailopHandler tbq  conn = do 
    iterateM_  ( \(lastetype,forbidtime) -> 
         do
              res <- atomically $ readTBQueue tbq
              tbqlen <- atomically $ lengthTBQueue tbq
              currtime <- getcurtimestamp 
              let curtime = fromIntegral currtime ::Double
              let et = etype res
              let etquan = quant res
              let etpr = price res
              let etimee = etime res
              let eordid = ordid res
              let eprofitgrid = eprofit res
              let eside = oside  res
              let diffbasetime  = case (et == "forbid") of
                                      True -> (fromIntegral etimee :: Double)
                                      False -> 0

              let newforbidtime = case (curtime<diffbasetime) of 
                                      True  -> diffbasetime
                                      False -> 0
              logact logByteStringStdout $ B.pack $ show ("len is !",tbqlen,et)
              
              when (et == "endcancel") $  do 
                   -- logact logByteStringStdout $ B.pack $ show ("bef cancel order!")
                    qryord <- queryorder
                    let sqryord = snd qryord
                    case sqryord of 
                        [] ->  return ()
                        _  ->  do 
                                   CE.catch ( do 
                                                  mapM_ funcgetorderid  sqryord
                                                  runRedis conn (ccanordertorediszset  curtime)

                                            ) ( \e -> do 
                                       logact logByteStringStdout $ B.pack $ show ("except!",(e::SomeException))
                                       )
                 `catch` (\(e :: SomeException) -> do
                    SI.hPutStrLn stderr $ "Gotscancelerror1: " ++ show e)


              when (et == "endopen") $ do 
                    (lastquan,(res,apr)) <- runRedis conn (cproordertorediszset curtime eside)
                    case (et == lastetype) of  
                       False -> do
                                    let side = case eside of 
                                                   BUY  -> "SELL"
                                                   SELL -> "BUY"
                                    let poside = case eside of 
                                                   BUY  -> "LONG"
                                                   SELL -> "SHORT"
                                    case res of 
                                       True  -> takeorder side (lastquan) apr poside
                                       False -> return () 
                       True  -> return ()
                 `catch` (\(e :: SomeException) -> do
                    SI.hPutStrLn stderr $ "Gotsopenerror1: " ++ show e)

              when (et == "merge") $ do 
                    runRedis conn (pexpandordertorediszset etquan etpr etimee curtime eside)
                 `catch` (\(e :: SomeException) -> do
                    SI.hPutStrLn stderr $ "Gotsmergeerror1: " ++ show e)

              when (et == "prep")   $  do 
                    runRedis conn $ do
                        preorcpreordertorediszset etquan eside etpr  currtime eprofitgrid curtime

              when (et == "cprep") $ do 
                    runRedis conn (preorcpreordertorediszset 0 eside etpr  0  0 curtime)
                 `catch` (\(e :: SomeException) -> do
                    SI.hPutStrLn stderr $ "Gotsscpreerror1: " ++ show e)

              when (et == "reset") $ do 
                    qrypos <- querypos
                    (quan,(pr,poside)) <- funcgetposinf qrypos
                    logact logByteStringStdout $ B.pack $ show ("reset detail is !",quan,pr,qrypos)
                    let astate = show $ fromEnum Done
                    let accugrid = getnewgrid quan 
                    let mergequan = quan
                    let side = case eside of 
                                   BUY  -> "BUY"
                                   SELL -> "SELL"
                    runRedis conn (settodefredisstate side "Done" astate "0"  pr  quan   accugrid  mergequan  curtime)-- set to Done prepare 
                 `catch` (\(e :: SomeException) -> do
                    SI.hPutStrLn stderr $ "Gotssreseterror1: " ++ show e)

              when (et == "acupd") $ do 
                    runRedis conn (acupdtorediszset etquan etpr etimee )
                `catch` (\(e :: SomeException) -> do
                   SI.hPutStrLn stderr $ "acpuerror: " ++ show e
                 )

              when (et == "fill") $ do 
                    logact logByteStringStdout $ B.pack $ show ("start fill command is !")
                    runRedis conn (endordertorediszset etquan etpr etimee curtime)  
                    logact logByteStringStdout $ B.pack $ show ("stop fill command is !")
                `catch` (\(e :: SomeException) -> do
                   SI.hPutStrLn stderr $ "fillerror: " ++ show e
                 )


              when (et == "init") $ do 
                  --  logact logByteStringStdout $ B.pack $ show ("aft init!")
                    runRedis conn (procproinitordertorediszset etquan etpr eordid etimee curtime)
                `catch` (\(e :: SomeException) -> do
                   SI.hPutStrLn stderr $ "initerror: " ++ show e
                 )

              when (et == "initopen") $ do 
                   -- logact logByteStringStdout $ B.pack $ show ("bef bopen!")
                    case (et == lastetype) of  
                       False -> do
                                  (lastquan,(res,apr)) <- runRedis conn (proordertorediszset  etpr curtime)
                                  let side = case eside of 
                                                   BUY  -> "BUY"
                                                   SELL -> "SELL"
                                  let poside = case eside of 
                                                   BUY  -> "LONG"
                                                   SELL -> "SHORT"
                                  case res of 
                                     True  -> takeorder side lastquan apr poside
                                     False -> return () 

                       True  -> return ()
                `catch` (\(e :: SomeException) -> do
                   SI.hPutStrLn stderr $ "initopenerror: " ++ show e
                 )


              return (et,newforbidtime)
      )  ("",0)
        

opclHandler :: TBQueue Opevent -> (TVar Curorder) -> RedisChannel -> ByteString  -> IO ()
opclHandler tbq ostvar  channel  msg = do
    let seperatemark = BLU.fromString ":::"
    let strturple = BL.fromStrict  $ B.drop 3 $ snd $  B.breakSubstring seperatemark  msg
    let restmsg = A.decode strturple :: Maybe WSevent  --Klinedata
    let detdata = wsdata $ fromJust restmsg
    let dettype = wstream $ fromJust restmsg
    when (dettype == "adausdt@kline_1m") $ do 
         let msgorigin = BLU.toString msg
         let msgitem = DLT.splitOn ":::" msgorigin 
         let order = DLT.splitOn "|" $  (msgitem!!0)
         let klinemsg = msgitem !! 1
         let orderquan = read (order !!4) :: Integer
         let orderpr = read (order !!5) :: Double
         let ordergrid = read (order !!6) :: Double
         let ordermergequan = read (order !!7) :: Int
         let ordid = order !!3
         let orderstater = DL.last order
         kline <- getmsgfromstr  klinemsg 
         let curpr = read $ kclose kline :: Double
         --logact logByteStringStdout $ B.pack $ show (orderstater,orderpr,curpr,ordergrid,"whynot!")
         let accugridlevel = getnewgridlevel orderquan
         let accugriddiff = getnewgriddiff ordergrid
         when ((orderstater == (show $ fromEnum Prepare)  ) == True) $ do
              atomically $ do
                     curorder <- readTVar ostvar
                     unsafeIOToSTM $  logact logByteStringStdout $ B.pack $ show ("orderstate bef buy process---------",orderstate curorder)
                     case ((orderstate curorder) == Prepare) of 
                        True  -> do 
                                    let pr = (fromInteger $  round $ curpr * (10^4))/(10.0^^4)
                                    let oside = orderside curorder
                                    let ochpostime = chpostime curorder 
                                    let aevent = Opevent "initopen"  0 pr 0 ordid 0 oside
                                    addeventtotbqueuestm aevent tbq
                                    let astate = Process
                                    let newcurorder = Curorder oside astate ochpostime
                                    writeTVar ostvar newcurorder
                        False -> do 
                                    return ()

         when ((orderstater == (show $ fromEnum Ccancel)) == True )  $ do
              let pr = (fromInteger $  round $ curpr * (10^4))/(10.0^^4)
              atomically $ do
                                curorder <- readTVar ostvar
                                let oside = orderside curorder
                                let ochpostime = chpostime curorder 
                                when ((oside == BUY  && ((orderpr-curpr)> accugriddiff)) || (oside == SELL && ((curpr-orderpr)> accugriddiff)))  $ do
                                     let aevent = Opevent "reset"  0 pr 0 ordid 0 oside
                                     addeventtotbqueuestm aevent tbq
                                     let astate =  Done
                                     let newcurorder = Curorder oside astate ochpostime
                                     writeTVar ostvar newcurorder


         when ((orderstater == (show $ fromEnum Cprepare) ) == True) $ do 
              let pr = (fromInteger $  round $ curpr * (10^4))/(10.0^^4)
              atomically $ do
                  curorder <- readTVar ostvar
                  let oside  = orderside curorder
                  let aevent = Opevent "endopen" 0 pr 0 ordid 0 oside
                  addeventtotbqueuestm aevent tbq

         when ((orderstater == (show $ fromEnum HalfDone) )==True) $ do 
              let pr = (fromInteger $  round $ curpr * (10^4))/(10.0^^4)
              atomically $ do
                  curorder <- readTVar ostvar
                  let oside  = orderside curorder
                  let aevent = Opevent "cprep" 0 pr 0 ordid 0 oside
                  addeventtotbqueuestm aevent tbq

         when ((DL.any (== orderstater) [(show $ fromEnum Cprocess),(show $ fromEnum Cpartdone),(show $ fromEnum Cproinit)]) == True ) $ do 
              atomically $ do
                  curorder <- readTVar ostvar
                  let oside  = orderside curorder
                  when (oside == BUY  && ((orderpr-curpr)> accugriddiff)) $ do
                    let aevent = Opevent "endcancel" 0 0 0 ordid 0 oside
                    addeventtotbqueuestm aevent tbq
                  when (oside == SELL && ((curpr-orderpr)> accugriddiff)) $ do
                    let aevent = Opevent "endcancel" 0 0 0 ordid 0 oside
                    addeventtotbqueuestm aevent tbq
              
              
    when (dettype /= "adausdt@kline_1m") $ do 
         let eventstr = fromJust $ detdata ^? key "e"
         let eventname = T.unpack $ outString eventstr 
         logact logByteStringStdout $ B.pack $ show ("event type is",eventname,detdata)
         when (eventname == "ORDER_TRADE_UPDATE") $ do 
              let curorderstate  = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "X") 
              let curside        = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "S")
              let cty            = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "z")
              let ccliorderid    = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "c")
              let cpr            = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "ap")
              let coriginprstr   = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "p")
              let corty          = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "q")
              let otimestampstr  = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "T")
              let corderid       = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "i")
              let curorderpr     = read cpr            :: Double
              let curquantyy     = read cty            :: Double
              let curortyy       = read corty          :: Double
              let coriginpr      = read coriginprstr   :: Double
              let otimestamp     = read otimestampstr  :: Int
              let curquanty      = round curquantyy    :: Integer
              let curorquanty    = round curortyy      :: Integer
              when (curorderstate == "FILLED") $ do 
                  let curcoin = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "N")
                  logact logByteStringStdout $ B.pack $ show ("choose filled---------",curorderstate)
                  logact logByteStringStdout $ B.pack $ show ("start filled---------")
                  atomically $ do
                        curorder <- readTVar ostvar
                        let oside = orderside curorder
                        case (oside,curside) of 
                            (BUY  ,"BUY" ) -> do 
                                              let aevent = Opevent "fill" curquanty curorderpr  otimestamp corderid 0 oside
                                              addeventtotbqueuestm aevent tbq
                                              let ochpostime = chpostime curorder 
                                              let astate = HalfDone
                                              let newcurorder = Curorder oside astate ochpostime
                                              writeTVar ostvar newcurorder
                                              unsafeIOToSTM $ logact logByteStringStdout $ B.pack $ show ("end open buy---------")
                            (BUY  ,"SELL") -> do 
                                              let aevent = Opevent "fill" curquanty curorderpr  otimestamp corderid 0 oside
                                              addeventtotbqueuestm aevent tbq
                                              let astate = Done
                                              let ochpostime = -1 
                                              let newcurorder = Curorder oside astate ochpostime
                                              writeTVar ostvar newcurorder
                                              unsafeIOToSTM $ logact logByteStringStdout $ B.pack $ show ("end close buy---------")
                            (SELL ,"SELL") -> do 
                                              let aevent = Opevent "fill" curquanty curorderpr  otimestamp corderid 0 oside
                                              addeventtotbqueuestm aevent tbq
                                              let ochpostime = chpostime curorder 
                                              let astate = HalfDone
                                              let newcurorder = Curorder oside astate ochpostime
                                              writeTVar ostvar newcurorder
                                              unsafeIOToSTM $ logact logByteStringStdout $ B.pack $ show ("end open sell---------")
                            (SELL ,"BUY" ) -> do 
                                              let aevent = Opevent "fill" curquanty curorderpr  otimestamp corderid 0 oside
                                              addeventtotbqueuestm aevent tbq
                                              let astate = Done
                                              let ochpostime = -1 
                                              let newcurorder = Curorder oside astate ochpostime
                                              writeTVar ostvar newcurorder
                                              unsafeIOToSTM $ logact logByteStringStdout $ B.pack $ show ("end close sell---------")

              when (curorderstate == "PARTIALLY_FILLED") $ do 
                  let curcoin = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "N")
                  logact logByteStringStdout $ B.pack $ show ("choose partfilled---------",curorderstate)
                  atomically $ do
                        curorder <- readTVar ostvar
                        let oside  = orderside curorder
                        let aevent = Opevent "merge" curquanty curorderpr otimestamp corderid 0 oside
                        addeventtotbqueuestm aevent tbq

              when ((DL.any (curorderstate ==) ["NEW"     ])==True) $ do 
                  atomically $ do
                      curorder <- readTVar ostvar
                      let oside = orderside curorder
                      let aevent = Opevent "init" curquanty coriginpr otimestamp corderid 0 oside
                      addeventtotbqueuestm aevent tbq

              when ((DL.any (curorderstate ==) ["CANCELED"])==True) $ do 
                  atomically $ do 
                      curorder <- readTVar ostvar
                      let oside = orderside curorder
                      let ochpostime = chpostime curorder 
                      unsafeIOToSTM $  logact logByteStringStdout $ B.pack $ show ("confirm cancel ---------",orderstate curorder)
                      let aevent = Opevent "reset" curorquanty curorderpr otimestamp corderid 0 oside
                      addeventtotbqueuestm aevent tbq
                      let astate = Done
                      let newcurorder = Curorder oside astate ochpostime
                      writeTVar ostvar newcurorder

         when (eventname == "ACCOUNT_UPDATE") $ do 
              let usdtbalo    = detdata ^.. key "a" .key "B" .values.filtered (has (key "a"._String.only "USDT"    )).key "cw"    -- !!0  
              let orderposo   = detdata ^.. key "a" .key "P" .values.filtered (has (key "s"._String.only "ADAUSDT" )).key "pa"    -- !!0
              let orderpro    = detdata ^.. key "a" .key "P" .values.filtered (has (key "s"._String.only "ADAUSDT" )).key "ep"    -- !!0
              let orderpos    = read $ T.unpack $ outString $ (!!0)  orderposo :: Integer
              let usdtbal     = round (read $ T.unpack $ outString $ (!!0)  usdtbalo :: Double) :: Int
              let orderpr     = read $ T.unpack $ outString $ (!!0)  orderpro  :: Double
              atomically $ do
                  curorder <- readTVar ostvar
                  let oside = orderside curorder
                  let aevent      = Opevent "acupd" orderpos  orderpr usdtbal "" 0 oside
                  addeventtotbqueuestm aevent tbq

detailanalysHandler :: TBQueue Cronevent -> TBQueue Opevent -> R.Connection -> (TVar Anlys.Depthset) -> (TVar Curorder) -> IO () 
detailanalysHandler tbcq tbq  conn tdepth orderst = do 
    iterateM_  ( \(timecountb,intervalcb) -> do
        res      <- atomically $ readTBQueue tbcq
        tbcqlen  <- atomically $ lengthTBQueue tbcq
        currtime <- getcurtimestamp 

        let timecounta   = (currtime `quot` 10000) 
        let timecountpred = (timecounta - timecountb) >= 1 
        let intervalcbpred = intervalcb == 0
        let curtime = fromIntegral currtime ::Double
        let et      = ectype res
        let etcont  = fromJust (eccont res)
        let etevent = fromJust (eoevent res) 
        let etpred = et == "resethdeoth"
        returnres  <-  case (timecountpred,intervalcbpred,etpred) of 
           (True ,True ,True)   -> do
                                  return (timecounta,intervalcb+1)                                  -- update timecounta  intervalcount +1
           (True ,False,True)   -> do  
                                  return (timecounta,intervalcb+1)                                  --no update timecounta     intervalcount+1
           (False,True ,True)   -> do  
                                  return (timecountb,0)
           (False,False,True)   -> do 
                                  return (timecountb,0)--reset intercalcount
           (_    ,_    ,_   )   -> return (timecountb,intervalcb)


        when (et == "forward")   $  do 
              anlytoBuy tbq conn etcont tdepth orderst--get all mseries from redis 


        when (et == "klinetor")  $  do 
              runRedis conn (sndklinetoredis etcont )

        when (et == "prep")   $  do 
                    let etquan = quant etevent
                    let etpr = price etevent
                    let etimee = etime etevent
                    let eordid = ordid etevent
                    let eprofitgrid = eprofit etevent
                    let eside = oside  etevent
                    runRedis conn $ do
                        preorcpreordertorediszset etquan eside etpr  currtime eprofitgrid curtime

        when (et == "resethdeoth") $
            do 
               logact logByteStringStdout $ B.pack $ show ("predi is ----- !",currtime,timecounta,timecountb,timecounta-timecountb ,timecountpred,intervalcbpred)
               case (timecountpred,intervalcbpred) of 
                  (True ,True )   -> do
                                          logact logByteStringStdout $ B.pack $ show ("success !")
                                          depthdata <- initupddepth conn
                                          atomically $ writeTVar tdepth depthdata
                                     `CE.catch` ( \e -> do 
                                              logact logByteStringStdout $ B.pack $ show ("except!",(e::SomeException))
                                              )
                  (True ,False)   -> do  
                                         return ()                                  --no update timecounta     intervalcount+1
                  (False,True )   -> do  
                                         return ()
                  (False,False)   -> do 
                                         return ()--reset intercalcount
               logact logByteStringStdout $ B.pack $ show ("reset is ----- !")


        when (et == "depthtor")  $  do 
              let originmsg        =  BL.fromStrict etcont
              let ressheeto        =  (A.decode originmsg) :: (Maybe Wdepseries)
              case ressheeto of 
                 Nothing -> return ()
                 _       -> do 
                    let ressheet = fromJust ressheeto
                    let curdepthu       =  depu  ressheet 
                    let curdepthU       =  depU  ressheet
                    let curdepthpu      =  deppu ressheet
                    let curdepthbid     =  bidsh ressheet
                    let curdepthask     =  asksh ressheet
                    let curdepthbidset  =  DHM.fromList $ curdepthbid 
                    let curdepthaskset  =  DHM.fromList $ curdepthask
                    let addintersectelem = DHM.fromList $ [(DL.last curdepthbid),(DL.head curdepthask)] 
                    atomically $ do 
                         befdepth <- readTVar tdepth
                         let befdepthu       =  Anlys.depu  befdepth 
                         let befdepthU       =  Anlys.depU  befdepth
                         let befdepthpu      =  Anlys.deppu befdepth
                         let befdepthbidset  =  Anlys.bidset befdepth
                         let befdepthaskset  =  Anlys.askset befdepth
                         let newhttppredi    =  befdepthu  == 0
                         let bulessthanpredi =  curdepthU  < befdepthu 
                         let ubigthanpredi   =  curdepthu  > befdepthu 
                         let continuprei     =  curdepthpu == befdepthu
                         case (newhttppredi,bulessthanpredi,ubigthanpredi,continuprei) of 
                              (_    ,True    ,True    ,_   ) -> do      --start merge
                                    let newbidhm = DHM.union curdepthbidset befdepthbidset 
                                    let newaskhm = DHM.union curdepthaskset befdepthaskset 
                                    let newinterhm = DHM.union addintersectelem $ DHM.intersection (curdepthbidset)  (curdepthaskset)
                                    let newdepthdata = Anlys.Depthset curdepthu curdepthU curdepthpu newinterhm newbidhm newaskhm
                                    writeTVar tdepth newdepthdata  
           --                         logact logByteStringStdout $ B.pack $ show ("depth merge-- !",curdepthpu,befdepthu)

                              (_    ,_       ,_      ,True ) -> do      --start merge
                                    let newbidhm = DHM.union curdepthbidset befdepthbidset 
                                    let newaskhm = DHM.union curdepthaskset befdepthaskset 
                                    let newinterhm = DHM.union addintersectelem $ DHM.intersection (curdepthbidset)  (curdepthaskset)
                                    let newdepthdata = Anlys.Depthset curdepthu curdepthU curdepthpu newinterhm newbidhm newaskhm
                                    writeTVar tdepth newdepthdata  
           --                         logact logByteStringStdout $ B.pack $ show ("depth merge-- !",curdepthpu,befdepthu)

                              (_    ,_       ,_      ,_    ) -> do      --need resync 
                                    -- send event to queue ,get mvar ,convert mvar to tvar ,update
                                   -- unsafeIOToSTM $ logact logByteStringStdout $ B.pack $ show ("atomic update depthdata!")
                                    let aevent = Cronevent "resethdeoth" Nothing Nothing
                                    addoeventtotbqueuestm aevent tbcq
                                  --  depthdata <- unsafeIOToSTM $ initupddepth conn
                                  --  writeTVar tdepth depthdata  
           --                         logact logByteStringStdout $ B.pack $ show ("depth new-- !"  ,curdepthpu,befdepthu)

                    return ()

        return returnres)  (0,0)

sndklinetoredis ::  ByteString -> Redis ()
sndklinetoredis  msg  = do 
    let mmsg = BL.fromStrict msg
    let test = A.decode mmsg :: Maybe Klinedata --Klinedata
    let abykeystr = BLU.fromString secondkey 
    let kline = case test of 
                    Just l -> l
    let ktf = ktime kline 
    let kt = fromInteger ktf :: Double
    let dst = show ktf
    let dop = kopen kline 
    let dcp = kclose kline
    let dhp = khigh kline 
    let dlp = klow kline 
    let abyvaluestr = msg 
                    
    void $ zadd abykeystr [(-kt,abyvaluestr)]
    void $ zremrangebyrank abykeystr 150 1000
      
sndtocacheHandler :: TBQueue Cronevent -> (TVar Anlys.Depthset)  -> RedisChannel -> ByteString -> IO ()
sndtocacheHandler tbq tdepth channel  msg = do 
      let strturple = BL.fromStrict    msg
      let restmsg = A.decode strturple :: Maybe WSevent  --Klinedata
      let detdata = wsdata $ fromJust restmsg
      let dettype = wstream $ fromJust restmsg
      when (dettype == "adausdt@kline_1m") $ do 
           let aevent = Cronevent "klinetor" (Just msg) Nothing 
           addoeventtotbqueue aevent tbq

      when (dettype == "adausdt@depth@500ms") $ do 
           let aevent = Cronevent "depthtor" (Just msg) Nothing
           addoeventtotbqueue aevent tbq

      
analysisHandler :: TBQueue Cronevent -> (TVar Anlys.Depthset)  ->  RedisChannel -> ByteString -> IO ()
analysisHandler tbq tdepth  channel msg = do 
      let aevent = Cronevent "forward" (Just msg) Nothing
      addoeventtotbqueue aevent tbq

mintocacheHandler :: RedisChannel -> ByteString -> IO ()
mintocacheHandler channel msg = do 
      conn <- connect defaultConnectInfo
      --how to control the interval
      minSticksToCache conn
      debugtime
      --SI.hPutStrLn stderr $ "Saw pmsg: " ++ unpack (decodeUtf8 channel) ++ unpack (decodeUtf8 msg)

getkeyfromredis :: Redis (Maybe ByteString)
getkeyfromredis  = do 
      let key = BLU.fromString "liskey"
      value <- get key
      case value of 
        Right v -> return  v

listenkeyHandler :: RedisChannel -> ByteString -> IO ()
listenkeyHandler channel msg = do
      conn <- connect defaultConnectInfo
      aaim <- runRedis conn (getkeyfromredis)
      pinghandledo aaim
      --SI.hPutStrLn stderr $ "Saw msg: " ++ T.unpack (decodeUtf8 msg)
      --debugtime


showChannels :: R.Connection -> IO ()
showChannels c = do
  resp :: Either Reply [ByteString] <- runRedis c $ sendRequest ["PUBSUB", "CHANNELS"]
  --liftIO $ SI.hPutStrLn stderr $ "Current redis channels: " ++ show resp
  debugtime


