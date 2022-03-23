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
      cacheHandler,
      showChannels,
      sklineHandler,
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
import Control.Exception
import Control.Monad.Trans (liftIO)
import Control.Concurrent
import Control.Lens
import Network.WebSockets as NW --(ClientApp, receiveData, sendClose, sendTextData,send,WebSocketsData)
import Network.WebSockets (sendPong)
import Network.WebSockets.Connection as NC
import Control.Concurrent.Async
import Control.Concurrent.STM
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
              void $ publish "cache:1" ("cache" <> msg)
              void $ publish "listenkey:1" ("listenkey" <> msg)
             -- NC.sendPong wc
            EQ ->
              return ()
            LT ->
              return ()


sendpongdo :: Integer -> NC.Connection -> IO ()
sendpongdo a conn = do
        liftIO $ print ("send Pong")
        case compare a 60000 of -- 300000= 5min
            GT -> do 
                  sendPong conn (T.pack $ show "")
                  sendPing conn (T.pack $ show "")
                  sendPong conn (T.pack $ show "")
            EQ ->
              return ()
            LT ->
              return ()
          

matchmsgfun :: ByteString -> Bool
matchmsgfun msg = matchmsg == matchamsg  
              where  
                  matchmsg = DB.drop 11 $ DB.take 24 msg 
                  matchamsg = BLU.fromString "adausdt@kline"


msgordertempdo :: ByteString -> ByteString -> Redis ()
msgordertempdo msg osdetail =  do
    let orderorigin = BLU.toString osdetail
    let order = DLT.splitOn "|" orderorigin 
    let orderstate = DL.last order
    --liftIO $ print (orderorigin)
    let orderquan =  read $ order!!4 :: Integer
    let seperate = BLU.fromString ":::"
    let mmsg = osdetail <> seperate <> msg

    when (((orderstate == "0")||(orderstate == "3")) && orderquan > 0 ) $ do 
        void $ publish "order:1" ("order" <> mmsg )
    
    when (matchmsgfun msg /= True ) $ do 
        void $ publish "order:1" ("order" <> mmsg )

generatehlsheet :: ByteString -> IO ()
generatehlsheet msg = do 
    conn <- connect defaultConnectInfo
    mseriesFromredis conn msg--get all mseries from redis 
    liftIO $ print "stop highlowsheet"
    ---generate high low point spreet
    ---quant analysis under high low (risk spreed) 
    ---return open/close event to redis 

msgsklinetoredis :: ByteString -> Integer -> Redis ()
msgsklinetoredis msg stamp = do
    when (matchmsgfun msg == True ) $ do 
      void $ publish "skline:1" ( msg)
      let abyvaluestr = msg
      let abykeystr = BLU.fromString secondkey
      let stamptime = fromInteger stamp :: Double
      void $ zadd abykeystr [(-stamptime,abyvaluestr)]
      void $ zremrangebyrank abykeystr 121 1000
      --add kline to redis zset for 1second
      --let test = A.decode msg :: Maybe Klinedata --Klinedata
      --liftIO $ print (test)
      -- store to kline seconds in  redis key as  1m 
msganalysistoredis :: ByteString -> Redis ()
msganalysistoredis msg = do
    when (matchmsgfun msg == True ) $ do 
      void $ publish "analysis:1" ( msg)

getliskeyfromredis :: Redis ()
getliskeyfromredis =  return ()

publishThread :: R.Connection -> NC.Connection -> IO (TVar a) -> IO ()
publishThread rc wc tvar =  
    forever $ do
      liftIO $ print ("loop is ---+++++")
      msgg <- NC.receive wc 
      message <- NC.receiveData wc 
      msg <- NC.receive wc 
      datamsg <- NC.receiveDataMessage wc 
      liftIO $ print ("date is ---",message)
      liftIO $ print ("date is ---",msgg)
      --liftIO $ T.putStrLn $ T.pack $ T.unpack message
      liftIO $ print ("control is ---",datamsg)
      curtimestamp <- round . (* 1000) <$> getPOSIXTime
      res <- runRedis rc (replydo curtimestamp ) 
      let orderitem = snd res
      let klineitem = fst res
      liftIO $ print (klineitem)
      let cachetime = case klineitem of
            Left _ ->  "some error"
            Right v ->   (v!!0)
      let orderdet = case orderitem of
            Left _ ->  "some error"
            Right v ->   (v!!0)
      let replydomarray = DLT.splitOn "|" $ BLU.toString cachetime
      --liftIO $ print ("-----------------------cachetime---------------------")
      --liftIO $ print (replydomarray)
      let replydores = (read (replydomarray !! 0)) :: Integer
      --liftIO $ print (replydores)
      let timediff = curtimestamp-replydores
      
  -----------------------------
  --check curtime need to update



      --get the data of kline cache ,check the invalid key number and update these
              
      --print (ktype test)
      --decide which event now is
      --1.check redis cache ,if cache valid time pass ,then send update command,detail two,one for stick update,one for put listenkey every 30min
      --2.check all open and close condition ,if match ,send open/close command
      --dispatch event to detail command
      runRedis rc $ do 
         msgcacheandpingtempdo timediff message wc 
--         msgpingtempdo timediff message
         --void $ publish "cache" ("cache" <> "aaaaaaa")
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
    liftIO $ print (curtime)


handlerThread :: R.Connection -> PubSubController -> IO (TVar a) -> IO ()
handlerThread conn ctrl tvar = forever $
       pubSubForever conn ctrl onInitialComplete
         `catch` (\(e :: SomeException) -> do
           SI.hPutStrLn stderr $ "Got error: " ++ show e
           threadDelay $ 50*1000)
--- do command detail operation here
  -- multi command operation now
--listenkeyHandler :: ByteString -> IO ()
--listenkeyHandler msg = SI.hPutStrLn stderr $ "Saw msg: " ++ unpack (decodeUtf8 msg)

opclHandler :: RedisChannel -> ByteString -> IO ()
opclHandler channel  msg = do
    -- open close order accroding to redis ada position and grid  and setnx and expire time and proccess uuid
    -- if msg send grid not match to redis grid ,cancel operation
    -- ==> command set from analysishandler ==> redis ==> publish ==> opclHandler
    --mtthread <- myThreadId
    conn <- connect defaultConnectInfo
    liftIO $ print ("start opcl ++++++++++++++++++++++++++++++++++++++++++++")
    let seperatemark = BLU.fromString ":::"
    let strturple = BL.fromStrict $ B.drop 3 $ snd $  B.breakSubstring seperatemark msg
    let restmsg = A.decode strturple :: Maybe WSevent  --Klinedata
    --liftIO $ print (restmsg)
    let detdata = wsdata $ fromJust restmsg
    --liftIO $ print (detdata)
    let dettype = wstream $ fromJust restmsg
    --liftIO $ print (dettype)
    when (dettype == "adausdt@kline_1m") $ do 
         let msgorigin = BLU.toString msg
         let msgitem = DLT.splitOn ":::" msgorigin 
         --liftIO $ print (msgitem)
         let order = DLT.splitOn "|" $  (msgitem!!0)
         let klinemsg = msgitem !! 1
         --liftIO $ print ("start take order")
         --liftIO $ print (klinemsg)
         let orderquan = read (order !!4) :: Integer
         let orderpr = read (order !!5) :: Double
         let orderstate = order !!6
         --liftIO $ print (orderquan)
         -- check need to close at what a price or need to open
         kline <- getmsgfromstr  klinemsg 
        -- liftIO $ print ("kline ++++++++++++++++++++++++++++++++++++++++++++")
         let curpr = read $ kclose kline :: Double
        -- liftIO $ print ("kline ++++++++++++++++++++++++++++++++++++++++++++")
         currtime <- getcurtimestamp 
         let curtime = fromInteger currtime ::Double
         when (orderstate == (show $ fromEnum Prepare)) $ do
              --let fpr = 0.01 + curpr
              let fpr =  curpr
              let pr = (fromInteger $  round $ fpr * (10^4))/(10.0^^4)
              runRedis conn (proordertorediszset orderquan pr curtime)
              --takeorder "BUY" orderquan pr 

         --when ((orderstate == (show $ fromEnum Cprepare)) && ((curpr -orderpr)>0.001)    ) $ do
        -- when ((orderstate == (show $ fromEnum Cprepare)) && ((curpr -orderpr)>0.001)    ) $ do
             -- liftIO $ print ("-------------start sell process---------------")
          --    let pr = curpr-0.01
          --    runRedis conn (cproordertorediszset orderquan pr curtime)
              --takeorder "SELL" orderquan pr 
         when ((orderstate == (show $ fromEnum Cprepare)) && ((curpr -orderpr)>0.003)    ) $ do
              let pr = (fromInteger $  round $ curpr * (10^4))/(10.0^^4)
              runRedis conn (ctestendordertorediszset orderquan pr curtime)


    when (dettype /= "adausdt@kline_1m") $ do 
         
         --liftIO $ print ("not kline ++++++++++++++++++++++++++++++++++++++++++++")
         let eventstr = fromJust $ detdata ^? key "e"
         let eventname = outString eventstr 
         --liftIO $ print (eventname)
         currtime <- getcurtimestamp 
         let curtime = fromInteger currtime ::Double
         when (eventname == "outboundAccountPosition") $ do 
         
              liftIO $ print ("enter outbound bal++++++++++++++++++++++++++++++++++++++++++++")
              let eventstr = fromJust $ detdata ^? key "e"
              let usdtcurball = (detdata ^.. key "B" .values.filtered (has (key "a"._String.only "USDT"))) !!0  
              let adacurball = (detdata ^.. key "B" .values.filtered (has (key "a"._String.only "ADA"))) !!0
              let usdtcurballl = fromJust $ usdtcurball ^? key "f" 
              let adacurballl = fromJust $ adacurball ^? key "f" 
              let usdtcurbal = read $ T.unpack $ outString usdtcurballl :: Double
              let adacurbal = read $ T.unpack $ outString adacurballl :: Double
              runRedis conn $ do  
                 balres <- getbalfromredis
                 orderres <- getorderfromredis
                 let adabal = read $ BLU.toString $ fromJust $ fromRight Nothing $ fst balres :: Double
                 let usdtbal = read $ BLU.toString $ fromJust $ fromRight Nothing $ snd balres :: Double
                 let quantyl =  fromRight [DB.empty] orderres
                 let quantyll = DLT.splitOn "|" $ BLU.toString  $ (quantyl !! 0 )
                 let quantylll = read $ (quantyll !! 4) :: Integer
                 let quantdouble = read $ (quantyll !! 4) :: Double
                 liftIO $ print (adabal,usdtbal,orderres,quantyl,adacurbal,usdtcurbal)
                 let adanum = floor adacurbal :: Integer
                 --liftIO $ print (usdtcurbal-usdtbal+0.1 )
                 when (usdtcurbal < usdtbal-0.1) $ do   -- that is now < past ,means to buy 
                     liftIO $ print ("enter buy pro++++++++++++++++++++++++++++++++++++++++++++")
                     liftIO $ print (usdtcurbal,quantdouble,usdtbal)
                     when (abs (adabal+ quantdouble-adacurbal) < 1 ) $ do -- record as end, current 1 : fee .need to business it after logic build
                         liftIO $ print ("enter execute pro++++++++++++++++++++++++++++++++++++++++++++")
                         hlfendordertorediszset adanum curtime  
                         setkvfromredis adakey $ show adacurbal 
                         setkvfromredis usdtkey $ show usdtcurbal 
                         --need to update bal key and do close request 
                     
                 when (usdtcurbal >= usdtbal-0.1) $ do   -- that is now >= past ,means to sell
                     --liftIO $ print ("enter sell pro++++++++++++++++++++++++++++++++++++++++++++")
                     when (abs (adacurbal+ quantdouble-adabal)< 1 ) $ do -- record as end
                         cendordertorediszset quantylll curtime  
                         setkvfromredis adakey $ show adacurbal 
                         setkvfromredis usdtkey $ show usdtcurbal 
                  --if lastrecord state == prepare  and diff <= quanty  then hlfendordertorediszset and closeorder
                  --if lastrecord state == cprepare  and diff <= quanty  then endordertorediszset
             
         when (eventname == "executionReport" ) $ do 
               --for this event come before outbound ,so need to add price first,after outbound come ,correct quanty
               --pexpandordertorediszset
              liftIO $ print ("enter excution ++++++++++++++++++++++++++++++++++++++++++++")
              let curorderstate = T.unpack $ outString $ fromJust $ detdata ^? key "X" 
              --liftIO $ print (curorderstate)
              when ((DL.any (curorderstate ==) ["FILLED","PARTIALLY_FILLED"])==True) $ do 
                 -- liftIO $ print ("1++++++++++++++++++++++++++++++++++++++++++++")
                  let cpr = T.unpack $ outString $ fromJust $ detdata ^? key "L" 
                  let cty = T.unpack $ outString $ fromJust $ detdata ^? key "l"
                  --liftIO $ print (cpr,cty)

                  let curorderpr = read cpr :: Double
                  --liftIO $ print ("2++++++++++++++++++++++++++++++++++++++++++++")
                  let curquantyy = read cty :: Double
                  let curquanty = round curquantyy :: Integer
                  --liftIO $ print ("3++++++++++++++++++++++++++++++++++++++++++++")
                  let curside = T.unpack $ outString $ fromJust $ detdata ^? key "S"
                  --liftIO $ print ("4++++++++++++++++++++++++++++++++++++++++++++")
                  let curcoin = T.unpack $ outString $ fromJust $ detdata ^? key "N" 
                  --liftIO $ print ("5++++++++++++++++++++++++++++++++++++++++++++")
                  --liftIO $ print (curorderpr,curquanty)
                  --liftIO $ print ("6++++++++++++++++++++++++++++++++++++++++++++")
                  --still need to  judge buy or sell
                  when (curside == "BUY" && curcoin == "ADA") $ do 
                       liftIO $ print ("enter merge order++++++++++++++++++++++++++++++++++++++++++++")
                       runRedis conn (pexpandordertorediszset curside curquanty curorderpr curtime)

                  when (curside == "SELL" && curcoin == "ADA") $ do 
                       liftIO $ print ("enter merge order++++++++++++++++++++++++++++++++++++++++++++")
                       runRedis conn (pexpandordertorediszset curside curquanty curorderpr curtime)
         
         --executionReport and outboundAccountPosition
        
   -- takeorder
   --change the state 
    --if type just = msg  and predication is qualified,then try get lock 
    --if type      = websocket account change/order token, release lock


addklinetoredis :: ByteString -> Redis ()
addklinetoredis msg  = do 
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
    let abyvaluestr =  BLU.fromString $ DL.intercalate "|" [dst,dop,dcp,dhp,dlp]
                    
    void $ zadd abykeystr [(-kt,abyvaluestr)]
    void $ zremrangebyrank abykeystr 121 1000
      --let msg = BL.fromStrict message
      --let test = A.decode msg :: Maybe Klinedata --Klinedata
      
sklineHandler :: RedisChannel -> ByteString -> IO ()
sklineHandler channel msg = do 
      conn <- connect defaultConnectInfo
      liftIO $ print ("start skline ++++++++++++++++++++++++++++++++++++++++++++")
      runRedis conn (addklinetoredis msg )
      debugtime

      
analysisHandler :: RedisChannel -> ByteString -> IO ()
analysisHandler channel msg = do 
      --conn <- connect defaultConnectInfo
      liftIO $ print ("start analysis ++++++++++++++++++++++++++++++++++++++++++++")
      generatehlsheet msg
      debugtime
      liftIO $ print ("end analysis ++++++++++++++++++++++++++++++++++++++++++++")

cacheHandler :: RedisChannel -> ByteString -> IO ()
cacheHandler channel msg = do 
      liftIO $ print ("start cache ++++++++++++++++++++++++++++++++++++++++++++")
      conn <- connect defaultConnectInfo
      getSticksToCache conn
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
  liftIO $ SI.hPutStrLn stderr $ "Current redis channels: " ++ show resp
  debugtime


