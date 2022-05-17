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
    liftIO $ logact logByteStringStdout $ B.pack $  show (matchacevent,matchorevent)                         
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

    when (DL.any (== orderstate) [(show $ fromEnum Cprepare),(show $ fromEnum Cprocess),(show $ fromEnum Cpartdone),(show $ fromEnum Cproinit),
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
      liftIO $ logact logByteStringStdout $ B.pack $ show ("index too large --------!",klineitem)
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
      logact logByteStringStdout $ message                              
      curtimestamp <- round . (* 1000) <$> getPOSIXTime
      let timecounta   = (curtimestamp `quot` 60000) 
      let timecountpred = (timecounta - timecountb) >= 1 
      let intervalcbpred = intervalcb == 0
      matchoevt  <- matchmsgfun message
      returnres  <-  case (timecountpred,intervalcbpred) of 
           (True ,True )   -> do
                                  sendpongdo wc
                                  let aevent = Cronevent "cachep"  message
                                  addoeventtotbqueue aevent tbq
                                  return (timecounta,intervalcb+1)                                  -- update timecounta  intervalcount +1
           (True ,False)   -> do  
                                  return (timecounta,intervalcb+1)                                  --no update timecounta     intervalcount+1
           (False,True )   -> do  
                                  return (timecountb,0)
           (False,False)   -> do 
                                  return (timecountb,0)--reset intercalcount



      when (matchoevt == "kline") $ do
           let aevent = Cronevent "kline"  message
           addoeventtotbqueue aevent tbq


      when (matchoevt == "or" || matchoevt == "ac" || matchoevt == "no") $ do
           let aevent = Cronevent "other"  message
           addoeventtotbqueue aevent tbq

      when (matchoevt == "depth") $ do
           let aevent = Cronevent "depth"  message
           addoeventtotbqueue aevent tbq

      return returnres )  (0,0)
      
detailpubHandler :: TBQueue Cronevent  -> R.Connection -> IO () 
detailpubHandler tbq conn = do 
    iterateM_  ( \(lastetype,forbidtime) -> do 
        res <- atomically $ readTBQueue tbq
        tbqlen <- atomically $ lengthTBQueue tbq
        logact logByteStringStdout $ B.pack $ show ("dopubb len is !",tbqlen)
        currtime <- getcurtimestamp 
        let curtime = fromInteger currtime ::Double
        let et      = ectype res
        let etcont  = eccont res

        when (et == "kline")   $  do 
           runRedis conn (msgklinedoredis currtime etcont )

        when (et == "depth")   $  do 
           runRedis conn $ do 
               void $ publish "depth:1" ( etcont)

        when (et == "other")   $  do 
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
    let curtime = fromInteger currtime ::Double
    return ()

handlerThread :: R.Connection -> PubSubController -> IO (TVar a) -> IO ()
handlerThread conn ctrl tvar = do 
    forever $
       pubSubForever conn ctrl onInitialComplete
         `catch` (\(e :: SomeException) -> do
           SI.hPutStrLn stderr $ "Got error: " ++ show e
           )




detailopHandler :: TBQueue Opevent ->  (TVar String) -> R.Connection -> IO () 
detailopHandler tbq ostvar conn = do 
    iterateM_  ( \(lastetype,forbidtime) -> 
      do
        logact logByteStringStdout $ B.pack $ show ("killbef thread!")
        res <- atomically $ readTBQueue tbq
        tbqlen <- atomically $ lengthTBQueue tbq
        logact logByteStringStdout $ B.pack $ show ("len is !",tbqlen)
        currtime <- getcurtimestamp 
        let curtime = fromInteger currtime ::Double
        let et = etype res
        let etquan = quant res
        let etpr = price res
        let etimee = etime res
        let eordid = ordid res
        let diffbasetime  = case (et == "forbid") of
                                True -> (fromIntegral etimee :: Double)
                                False -> 0

        let newforbidtime = case (curtime<diffbasetime) of 
                                True  -> diffbasetime
                                False -> 0
        
        when (et == "scancel") $  do 
              logact logByteStringStdout $ B.pack $ show ("bef cancel order!")
              qryord <- queryorder
              let sqryord = snd qryord
              case sqryord of 
                  [] ->  return ()
                  _  ->  do 
                             CE.catch (mapM_ funcgetorderid  sqryord) ( \e -> do 
                                 logact logByteStringStdout $ B.pack $ show ("except!",(e::SomeException))
                                 )
                             runRedis conn (ccanordertorediszset  curtime)


        when (et == "sopen") $ do 
              (lastquan,(res,apr)) <- runRedis conn (cproordertorediszset curtime)
              case (et == lastetype) of  
                 False -> do
                              case res of 
                                 True  -> takeorder "SELL" (lastquan) apr
                                 False -> return () 
                 True  -> return ()

        when (et == "merge") $ do 
              runRedis conn (pexpandordertorediszset etquan etpr etimee curtime)

        when (et == "cprep") $ do 
              runRedis conn (preorcpreordertorediszset 0 etpr  0  0 curtime)

        when (et == "reset") $ do 
              qrypos <- querypos
              (quan,pr) <- funcgetposinf qrypos
              let astate = show $ fromEnum Done
              let accugrid = case quan of 
                                  x|x<=200            -> 0.0005
                                  x|x<=360            -> 0.0005
                                  x|x<=500            -> 0.0005
                                  x|x<=1000&&x>500    -> 0.0005
                                  x|x<=2000&&x>1000   -> 0.001
                                  x|x<=4000&&x>2000   -> 0.01
                                  x|x<=8000&&x>4000   -> 0.03
                                  x|x<=16000&&x>8000  -> 0.09
                                  _                   -> 0.09
              runRedis conn (settodefredisstate "SELL" "Done" astate "0"  pr  quan   accugrid  0  curtime)-- set to Done prepare 

        when (et == "acupd") $ do 
              runRedis conn (acupdtorediszset etquan etpr etimee )

        when (et == "fill") $ do 
              runRedis conn (endordertorediszset etquan etpr etimee curtime)  

        when (et == "init") $ do 
              logact logByteStringStdout $ B.pack $ show ("aft init!")
              runRedis conn (procproinitordertorediszset etquan etpr eordid etimee curtime)

        when (et == "bopen") $ do 
              logact logByteStringStdout $ B.pack $ show ("bef bopen!")
              case (et == lastetype) of  
                 False -> do
                            (lastquan,(res,apr)) <- runRedis conn (proordertorediszset  etpr curtime)
                            case res of 
                               True  -> takeorder "BUY" lastquan apr
                               False -> return () 
                 True  -> return ()


        return (et,newforbidtime))  ("",0)
        

opclHandler :: TBQueue Opevent -> (TVar String) -> RedisChannel -> ByteString  -> IO ()
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
         logact logByteStringStdout $ B.pack $ show (orderpr,curpr,ordergrid,"whynot!")
         let accugridlevel = case orderquan of 
                                  x|x<=150            -> 4
                                  x|x<=260&&x>150     -> 8
                                  x|x>=260&&x<500     -> 12
                                  x|x<=1000&&x>500    -> 20
                                  x|x<=2000&&x>1000   -> 32
                                  x|x<=4000&&x>2000   -> 64
                                  x|x<=8000&&x>4000   -> 120
                                  x|x<=16000&&x>8000  -> 200
                                  _                   -> 128 
         when ((orderstater == (show $ fromEnum Prepare)  ) == True) $ do
              atomically $ do
                     orderstate <- readTVar ostvar
                     case (orderstate == (show $ fromEnum Prepare)) of 
                        True  -> do 
                                    let pr = (fromInteger $  round $ curpr * (10^4))/(10.0^^4)
                                    let aevent = Opevent "bopen"  0 pr 0 ordid
                                    addeventtotbqueuestm aevent tbq
                                    let astate = show $ fromEnum Process
                                    writeTVar ostvar astate
                        False -> do 
                                    return ()

         when ((orderstater == (show $ fromEnum Process) && ((curpr-orderpr)> 0.001 ) ) == True) $ do
              let pr = (fromInteger $  round $ curpr * (10^4))/(10.0^^4)
              atomically $ do
                                let aevent = Opevent "reset"  0 pr 0 ordid
                                addeventtotbqueuestm aevent tbq
                                let astate = show $ fromEnum Done
                                writeTVar ostvar astate

         when ((orderstater == (show $ fromEnum Cprepare) ) == True) $ do 
              let pr = (fromInteger $  round $ curpr * (10^4))/(10.0^^4)
              let aevent = Opevent "sopen" 0 pr 0 ordid
              addeventtotbqueue aevent tbq

         when ((orderstater == (show $ fromEnum HalfDone) )==True) $ do 
              let pr = (fromInteger $  round $ curpr * (10^4))/(10.0^^4)
              let aevent = Opevent "cprep" 0 pr 0 ordid
              addeventtotbqueue aevent tbq

         when ((DL.any (== orderstater) [(show $ fromEnum Ccancel),(show $ fromEnum Cprocess),(show $ fromEnum Cpartdone),(show $ fromEnum Cproinit)] && ((orderpr-curpr)> (accugridlevel*ordergrid))  ) == True ) $ do 
              let aevent = Opevent "scancel" 0 0 0 ordid
              addeventtotbqueue aevent tbq
              
              
    when (dettype /= "adausdt@kline_1m") $ do 
         let eventstr = fromJust $ detdata ^? key "e"
         let eventname = T.unpack $ outString eventstr 
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
              when ((DL.any (curorderstate ==) ["FILLED","PARTIALLY_FILLED"])==True) $ do 
                       let curcoin = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "N")
                       when (curquanty < curorquanty)  $ do 
                          logact logByteStringStdout $ B.pack $ show ("bef order update partfilled redis---------")
                          let aevent = Opevent "merge" curquanty curorderpr otimestamp corderid
                          addeventtotbqueue aevent tbq
                       when (curquanty == curorquanty) $ do 
                          when (curside == "BUY")  $  do 
                               let aevent = Opevent "fill" curquanty curorderpr  otimestamp corderid
                               addeventtotbqueue aevent tbq
                          when (curside == "SELL") $  do 
                               atomically $ do
                                   let aevent = Opevent "fill" curquanty curorderpr  otimestamp corderid
                                   addeventtotbqueuestm aevent tbq
                                   let astate = show $ fromEnum Done
                                   writeTVar ostvar astate

              when ((DL.any (curorderstate ==) ["NEW"])==True) $ do 
                      let aevent = Opevent "init" curquanty coriginpr otimestamp corderid
                      addeventtotbqueue aevent tbq

              when ((DL.any (curorderstate ==) ["CANCELED"])==True) $ do 
                      let aevent = Opevent "reset" curorquanty curorderpr otimestamp corderid
                      addeventtotbqueue aevent tbq

         when (eventname == "ACCOUNT_UPDATE") $ do 
              let usdtbalo    = detdata ^.. key "a" .key "B" .values.filtered (has (key "a"._String.only "USDT"    )).key "cw"    -- !!0  
              let orderposo   = detdata ^.. key "a" .key "P" .values.filtered (has (key "s"._String.only "ADAUSDT" )).key "pa"    -- !!0
              let orderpro    = detdata ^.. key "a" .key "P" .values.filtered (has (key "s"._String.only "ADAUSDT" )).key "ep"    -- !!0
              let orderpos    = read $ T.unpack $ outString $ (!!0)  orderposo :: Integer
              let usdtbal     = round (read $ T.unpack $ outString $ (!!0)  usdtbalo :: Double) :: Int
              let orderpr     = read $ T.unpack $ outString $ (!!0)  orderpro  :: Double
              let aevent      = Opevent "acupd" orderpos  orderpr usdtbal ""
              addeventtotbqueue aevent tbq

detailanalysHandler :: TBQueue Cronevent  -> R.Connection -> (TVar Anlys.Depthset) -> (TVar String) -> IO () 
detailanalysHandler tbq conn tdepth orderst = do 
    iterateM_  ( \(timecountb,intervalcb) -> do
        logact logByteStringStdout $ B.pack $ show ("analys thread!")
        res      <- atomically $ readTBQueue tbq
        logact logByteStringStdout $ B.pack $ show ("tbq is !",res)
        tbqlen   <- atomically $ lengthTBQueue tbq
        logact logByteStringStdout $ B.pack $ show ("len is !",tbqlen)
        currtime <- getcurtimestamp 

        let timecounta   = (currtime `quot` 10000) 
        let timecountpred = (timecounta - timecountb) >= 1 
        let intervalcbpred = intervalcb == 0
        logact logByteStringStdout $ B.pack $ show ("predi is ----- !",currtime,timecounta-timecountb ,timecountpred,intervalcbpred)
        returnres  <-  case (timecountpred,intervalcbpred) of 
           (True ,True )   -> do
                                  return (timecounta,intervalcb+1)                                  -- update timecounta  intervalcount +1
           (True ,False)   -> do  
                                  return (timecounta,intervalcb+1)                                  --no update timecounta     intervalcount+1
           (False,True )   -> do  
                                  return (timecountb,0)
           (False,False)   -> do 
                                  return (timecountb,0)--reset intercalcount

        let curtime = fromInteger currtime ::Double
        let et      = ectype res
        let etcont  = eccont res

        when (et == "forward")   $  do 
              anlytoBuy conn etcont tdepth orderst--get all mseries from redis 

        when (et == "klinetor")  $  do 
              runRedis conn (sndklinetoredis etcont )

        when (et == "resethdeoth") $
            do 
               case (timecountpred,intervalcbpred) of 
                  (True ,True )   -> do
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
                                    unsafeIOToSTM $ logact logByteStringStdout $ B.pack $ show ("atomic update depthdata!")
                                    let aevent = Cronevent "resethdeoth"  B.empty
                                    addoeventtotbqueuestm aevent tbq
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
           let aevent = Cronevent "klinetor" msg 
           addoeventtotbqueue aevent tbq

      when (dettype == "adausdt@depth@500ms") $ do 
           let aevent = Cronevent "depthtor" msg 
           addoeventtotbqueue aevent tbq

      
analysisHandler :: TBQueue Cronevent -> (TVar Anlys.Depthset)  ->  RedisChannel -> ByteString -> IO ()
analysisHandler tbq tdepth  channel msg = do 
      let aevent = Cronevent "forward" msg 
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


