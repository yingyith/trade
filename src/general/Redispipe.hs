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
      sndtocacheHandler,
      acupdHandler,
      detailopHandler,
      analysisHandler

    ) where
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`

import Database.Redis as R
import Data.Monoid ((<>))
import Data.Time
import GHC.Generics
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
import Logger
import Colog (LogAction,logByteStringStdout)
import Redisutils


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
--the predications of rule system 


msgcacheandpingtempdo :: Integer -> ByteString -> NC.Connection-> Redis ()
msgcacheandpingtempdo a msg wc = do
        case compare a 60000 of -- 300000= 5min
        --case compare a 300000 of -- 300000= 5min
            GT -> do 
              void $ publish "minc:1" ("cache" <> msg)
              void $ publish "listenkey:1" ("listenkey" <> msg)
             -- NC.sendPong wc
            EQ ->
              return ()
            LT ->
              return ()


sendpongdo :: Integer -> NC.Connection -> IO ()
sendpongdo a conn = do
        --liftIO $ print ("send Pong")
        case compare a 60000 of -- 300000= 5min
            GT -> do 
                  sendPong conn (T.pack $ show "")
                  sendPing conn (T.pack $ show "")
                  sendPong conn (T.pack $ show "")
            EQ ->
              return ()
            LT ->
              return ()
          

matchmsgfun :: ByteString -> Redis String
matchmsgfun msg = do
    let  matchkline = DB.drop 11 $ DB.take 24 msg 
    let  matchkmsg = BLU.fromString "adausdt@kline"
    let  matchacevent = DB.drop 90 $ DB.take 103 msg 
    let  matchacmsg = BLU.fromString "ACCOUNT_UPDATE"
    let  matchorevent = DB.drop 90 $ DB.take 108 msg 
    let  matchormsg = BLU.fromString "ORDER_TRADE_UPDATE"
   -- liftIO $ logact logByteStringStdout $ B.pack $  show (msg)                         
    liftIO $ logact logByteStringStdout $ B.pack $  show (matchacevent,matchorevent)                         
    let klinepredi = matchkline == matchkmsg
    let acpredi = matchacevent == matchacmsg
    let orpredi = matchorevent == matchormsg
    case (klinepredi,acpredi,orpredi) of 
        (True  , _     ,_     ) -> return "kline"
        (_     , True  ,_     ) -> return "ac"
        (_     , _     ,True  ) -> return "or"
        (_     , _     ,_     ) -> return "no"


msgordertempdo :: ByteString -> ByteString -> Redis ()
msgordertempdo msg osdetail =  do
    let orderorigin = BLU.toString osdetail
    let order = DLT.splitOn "|" orderorigin 
    let orderstate = DL.last order
    --liftIO $ print (orderorigin)
    let orderquan =  read $ order!!4 :: Integer
    let seperate = BLU.fromString ":::"
    let mmsg = osdetail <> seperate <> msg
   -- liftIO $ logact logByteStringStdout mmsg                          
    matchevent <- matchmsgfun msg
    liftIO $ logact logByteStringStdout $ B.pack $  show (orderstate,matchevent)                         

    --when (((orderstate == "0")||(orderstate == "3")) && orderquan > 0 ) $ do 

    when (DL.any (== orderstate) [(show $ fromEnum Cprepare),(show $ fromEnum Cprocess),(show $ fromEnum Cpartdone),(show $ fromEnum Cproinit),
                                  (show $ fromEnum Prepare),(show $ fromEnum Process),(show $ fromEnum Ppartdone),(show $ fromEnum Proinit)]  )  $ do 
        liftIO $ logact logByteStringStdout "take order part"                             
        void $ publish "order:1" ("order" <> mmsg )
    
    when (matchevent == "ac" ) $ do 
        liftIO $ logact logByteStringStdout "take order partit"                             
        void $ publish "ac:1" ("ac" <> mmsg )

   -- when (matchevent == "or" ) $ do 
   --     liftIO $ logact logByteStringStdout "take order partit"                             
   --     void $ publish "order:1" ("order" <> mmsg )

generatehlsheet :: ByteString -> IO ()
generatehlsheet msg = do 
    conn <- connect defaultConnectInfo
    mseriesFromredis conn msg--get all mseries from redis 
    --liftIO $ print "stop highlowsheet"
    ---generate high low point spreet
    ---quant analysis under high low (risk spreed) 
    ---return open/close event to redis 

msgsklinetoredis :: ByteString -> Integer -> Redis ()
msgsklinetoredis msg stamp = do
    matchevent <- matchmsgfun msg
    when (matchevent == "kline" ) $ do 
      void $ publish "sndc:1" ( msg)
      --logact logByteStringStdout $ msg                              
      let abyvaluestr = msg
      let abykeystr = BLU.fromString secondkey
      let stamptime = fromInteger stamp :: Double
      void $ zadd abykeystr [(-stamptime,abyvaluestr)]
      void $ zremrangebyrank abykeystr 150 1000
      --add kline to redis zset for 1second
      --let test = A.decode msg :: Maybe Klinedata --Klinedata
      --liftIO $ print (test)
      -- store to kline seconds in  redis key as  1m 
msganalysistoredis :: ByteString -> Redis ()
msganalysistoredis msg = do
    matchevent <- matchmsgfun msg
    when (matchevent == "kline" ) $ do 
      void $ publish "analysis:1" ( msg)

getliskeyfromredis :: Redis ()
getliskeyfromredis =  return ()

publishThread :: R.Connection -> NC.Connection -> IO (TVar a) -> ThreadId -> IO ()
publishThread rc wc tvar ptid = do 
    forever $ do
      message <- (NC.receiveData wc)
      logact logByteStringStdout $ message                              
      curtimestamp <- round . (* 1000) <$> getPOSIXTime
      res <- runRedis rc (replydo curtimestamp ) 
      --let aa = (1/0) 
      let orderitem = snd res
      let klineitem = fst res
      logact logByteStringStdout $ B.pack $ show ("index too large --------!",klineitem,orderitem)
      let cachetime = case klineitem of
            Left _  ->  "some error"
            Right v ->   (v!!0)
      let orderdet  = case orderitem of
            Left _  ->  "some error"
            Right v ->   (v!!0)
      let replydomarray = DLT.splitOn "|" $ BLU.toString cachetime
      let replydores = (read (replydomarray !! 0)) :: Integer
      let timediff = curtimestamp-replydores
      
      --decide which event now is
      --1.check redis cache ,if cache valid time pass ,then send update command,detail two,one for stick update,one for put listenkey every 30min
      --2.check all open and close condition ,if match ,send open/close command
      --dispatch event to detail command
      runRedis rc $ do 
         msgcacheandpingtempdo timediff message wc 
         msgsklinetoredis message curtimestamp
         msganalysistoredis message
         msgordertempdo message orderdet
      sendpongdo timediff  wc

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

detailopHandler :: TBQueue Opevent  -> IO () 
detailopHandler tbq = do 
    conn <- (connect defaultConnectInfo)
    iterateM_  ( \lastetype -> do
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

        when (et == "scancel") $  do 
              qryord <- queryorder
              let sqryord = snd qryord
              case sqryord of 
                  [] ->  return ()
                  _  ->  do 
                             CE.catch (mapM_ funcgetorderid  sqryord) ( \e -> do 
                                 logact logByteStringStdout $ B.pack $ show ("except!",(e::SomeException)))
                             runRedis conn (ccanordertorediszset  curtime)

        when (et == "bopen") $ do 
              logact logByteStringStdout $ B.pack $ show ("bef bopen!")
              case (et == lastetype) of  
                 False -> do
                            (lastquan,(res,apr)) <- runRedis conn (proordertorediszset  etpr curtime)
                            logact logByteStringStdout $ B.pack $ show ("aft bopen!")
                            case res of 
                               True  -> takeorder "BUY" lastquan apr
                               False -> return () 
                 True  -> return ()

        when (et == "sopen") $ do 
              (lastquan,(res,apr)) <- runRedis conn (cproordertorediszset curtime)
              case (et == lastetype) of  
                 False -> do
                              case res of 
                                 True  -> takeorder "SELL" lastquan apr
                                 False -> return () 
                 True  -> return ()

        when (et == "merge") $ do 
              runRedis conn (pexpandordertorediszset etquan etpr etimee curtime)

        when (et == "reset") $ do 
              qrypos <- querypos
              (quan,pr) <- funcgetposinf qrypos
              let astate = show $ fromEnum Done
              runRedis conn (settodefredisstate "BUY" "Done" astate "0"  pr  quan   0  0  curtime)-- set to Done prepare 
             -- runRedis conn (procproinitordertorediszset etquan etpr eordid etimee curtime)

        when (et == "acupd") $ do 
              logact logByteStringStdout $ B.pack $ show ("befacupd!")
              runRedis conn (acupdtorediszset etquan etpr etimee )
              logact logByteStringStdout $ B.pack $ show ("aftacupd!")

        when (et == "fill") $ do 
              runRedis conn (endordertorediszset etquan etpr etimee curtime)  

        when (et == "init") $ do 
              logact logByteStringStdout $ B.pack $ show ("bef init!")
              runRedis conn (procproinitordertorediszset etquan etpr eordid etimee curtime)
              logact logByteStringStdout $ B.pack $ show ("aft init!")


        logact logByteStringStdout $ B.pack $ show ("kill bef thread!",res)
        return et)  ""
        

opclHandler :: TBQueue Opevent -> R.Connection -> RedisChannel -> ByteString -> IO ()
opclHandler tbq conn channel  msg = do
    let seperatemark = BLU.fromString ":::"
    let strturple = BL.fromStrict  $ B.drop 3 $ snd $  B.breakSubstring seperatemark  msg
    let restmsg = A.decode strturple :: Maybe WSevent  --Klinedata
    let detdata = wsdata $ fromJust restmsg
    let dettype = wstream $ fromJust restmsg
    --async $ (atomically $ writeTBQueue tbq "nownow" ) 
    when (dettype == "adausdt@kline_1m") $ do 
         let msgorigin = BLU.toString msg
         let msgitem = DLT.splitOn ":::" msgorigin 
         let order = DLT.splitOn "|" $  (msgitem!!0)
         let klinemsg = msgitem !! 1
         let orderquan = read (order !!4) :: Integer
         let orderpr = read (order !!5) :: Double
         let ordergrid = read (order !!6) :: Double
         let ordid = order !!3
         let orderstate = DL.last order
         kline <- getmsgfromstr  klinemsg 
         let curpr = read $ kclose kline :: Double
         logact logByteStringStdout $ B.pack $ show (orderstate,orderpr,curpr,ordergrid,"whynot!")
        -- when ((orderstate == (show $ fromEnum Prepare)) &&  ((curpr -orderpr)>((-0.5)*ordergrid)    ))$ do  if < ,reset to origin
         when ((orderstate == (show $ fromEnum Prepare)) )$ do
              let pr = (fromInteger $  round $ curpr * (10^4))/(10.0^^4)
              let aevent = Opevent "bopen"  0 pr 0 ordid
              addeventtotbqueue aevent tbq
              logact logByteStringStdout $ B.pack  ("aftentertake order do ---------------------")

         when ((orderstate == (show $ fromEnum Cprepare)) ) $ do
              let pr = (fromInteger $  round $ curpr * (10^4))/(10.0^^4)
              let aevent = Opevent "sopen" 0 pr 0 ordid
              addeventtotbqueue aevent tbq

         when (DL.any (== orderstate) [(show $ fromEnum Ccancel),(show $ fromEnum Cprocess),(show $ fromEnum Cpartdone),(show $ fromEnum Cproinit)] && ((orderpr-curpr)> (3*ordergrid))  )  $ do 
              let aevent = Opevent "scancel" 0 0 0 ordid
              addeventtotbqueue aevent tbq
              
              
    when (dettype /= "adausdt@kline_1m") $ do 
         let eventstr = fromJust $ detdata ^? key "e"
         let eventname = T.unpack $ outString eventstr 
         logact logByteStringStdout $ B.pack  $ show ("beforderupdate01 ---------",show eventstr)
         when (eventname == "ORDER_TRADE_UPDATE") $ do 
              --logact logByteStringStdout $ B.pack  $ show ("beforderupdate ---------")
              let curorderstate = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "X") 
              let curside        = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "S")
              let cty            = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "z")
              let ccliorderid            = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "c")
              let cpr            = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "ap")
              let coriginprstr            = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "p")
              let corty          = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "q")
              let otimestampstr  = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "T")
              let corderid  = T.unpack $ outString $ fromJust $ (detdata ^? key "o" .key "i")
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
                          logact logByteStringStdout $ B.pack $ show ("bef order update filled redis---------")
                          let aevent = Opevent "fill" curquanty curorderpr  otimestamp corderid
                          addeventtotbqueue aevent tbq

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
              logact logByteStringStdout $ B.pack  $ show ("acupdate ---------",usdtbalo,orderposo,orderpro)
              --let usdtbalo    = read $ T.unpack $ outString $ fromJust usdtbalo  :: Int 
              let orderpos    = read $ T.unpack $ outString $ (!!0)  orderposo :: Integer
              let usdtbal     = round (read $ T.unpack $ outString $ (!!0)  usdtbalo :: Double) :: Int
              let orderpr     = read $ T.unpack $ outString $ (!!0)  orderpro  :: Double
              let aevent      = Opevent "acupd" orderpos  orderpr usdtbal ""
              addeventtotbqueue aevent tbq




acupdHandler :: RedisChannel -> ByteString -> IO ()
acupdHandler channel  msg = do
    conn <- connect defaultConnectInfo
    logact logByteStringStdout $ B.pack  $ show ("beforderupdate--00 ---------")
    let seperatemark = BLU.fromString ":::"
    let strturple = BL.fromStrict $ B.drop 3 $ snd $  B.breakSubstring seperatemark msg
    let restmsg = A.decode strturple :: Maybe WSevent  --Klinedata
    let detdata = wsdata $ fromJust restmsg
    let dettype = wstream $ fromJust restmsg
    logact logByteStringStdout $ B.pack  $ show ("beforderupdate00 ---------",show dettype,show detdata)
    when (dettype /= "adausdt@kline_1m") $ do 
         let eventstr = fromJust $ detdata ^? key "e"
         let eventname = outString eventstr 
         currtime <- getcurtimestamp 
         let curtime = fromInteger currtime ::Double
         logact logByteStringStdout $ B.pack  $ show ("beforderupdate01 ---------",show eventstr)
         when (eventname == "ACCOUNT_UPDATE") $ do 
              let eventstr = fromJust $ detdata ^? key "e"
              let usdtcurballll = detdata ^.. key "a" .key "B" .values.filtered (has (key "a"._String.only "USDT"    ))    -- !!0  
              let orderballll   = detdata ^.. key "a" .key "P" .values.filtered (has (key "a"._String.only "ADAUSDT" ))    -- !!0
              let usdtcurball = usdtcurballll !! 0
              let ordercurball = orderballll !! 0
              let usdtcurballl = fromJust $ usdtcurball ^? key "f" 
              let usdtcurbal = read $ T.unpack $ outString usdtcurballl :: Double
              let adacurbal = read $ T.unpack $ outString ordercurball :: Integer
              runRedis conn $ do  
                 balres <- getbalfromredis
                 orderres <- getorderfromredis
                 let adabal = read $ BLU.toString $ fromJust $ fromRight Nothing $ fst balres :: Double
                 let usdtbal = read $ BLU.toString $ fromJust $ fromRight Nothing $ snd balres :: Double
                 let quantyl =  fromRight [DB.empty] orderres
                 let quantyll = DLT.splitOn "|" $ BLU.toString  $ (quantyl !! 0 )
                 let quantylll = read $ (quantyll !! 4) :: Integer
                 let quantdouble = read $ (quantyll !! 4) :: Double
                 setkvfromredis adakey $ show adacurbal 
                 setkvfromredis usdtkey $ show usdtcurbal 

sndklinetoredis :: ByteString -> Redis ()
sndklinetoredis msg  = do 
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
    --let abyvaluestr =  BLU.fromString $ DL.intercalate "|" [dst,dop,dcp,dhp,dlp]
    let abyvaluestr = msg 
                    
    void $ zadd abykeystr [(-kt,abyvaluestr)]
    void $ zremrangebyrank abykeystr 150 1000
      --let msg = BL.fromStrict message
      --let test = A.decode msg :: Maybe Klinedata --Klinedata
      
sndtocacheHandler :: RedisChannel -> ByteString -> IO ()
sndtocacheHandler channel msg = do 
      conn <- connect defaultConnectInfo
      runRedis conn (sndklinetoredis msg )
      debugtime

      
analysisHandler :: RedisChannel -> ByteString -> IO ()
analysisHandler channel msg = do 
      --conn <- connect defaultConnectInfo
      --liftIO $ print ("start analysis ++++++++++++++++++++++++++++++++++++++++++++")
      generatehlsheet msg
      debugtime
      --liftIO $ print ("end analysis ++++++++++++++++++++++++++++++++++++++++++++")

mintocacheHandler :: RedisChannel -> ByteString -> IO ()
mintocacheHandler channel msg = do 
      --liftIO $ print ("start cache ++++++++++++++++++++++++++++++++++++++++++++")
      conn <- connect defaultConnectInfo
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


