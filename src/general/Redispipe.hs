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
import Network.WebSockets (ClientApp, receiveData, sendClose, sendTextData)
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
import Httpstructure
import Rediscache
import Globalvar
import Order


replydo :: Redis (Either Reply [ByteString], Either Reply [ByteString])
replydo = do
        let akey = BLU.fromString fivemkey
        item <- zrange akey 0 1
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


msgcacheandpingtempdo :: Integer -> ByteString -> Redis ()
msgcacheandpingtempdo a msg = do
        case compare a 300000 of -- 300000= 5min
        --case compare a 300000 of -- 300000= 5min
            GT -> do 
              void $ publish "cache:1" ("cache" <> msg)
              void $ publish "listenkey:1" ("listenkey" <> msg)
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
    let orderquan =  read $ order!!4 :: Integer
    let seperate = BLU.fromString ":::"
    let mmsg = osdetail <> seperate <> msg

    when (orderstate == "0" && orderquan > 0 ) $ do 
        void $ publish "order:1" ("order" <> mmsg )
    
    when (matchmsgfun msg /= True ) $ do 
        void $ publish "order:1" ("order" <> mmsg )

generatehlsheet :: ByteString -> IO ()
generatehlsheet msg = do 
         conn <- connect defaultConnectInfo
         mseriesFromredis conn msg--get all mseries from redis 
         ---generate high low point spreet
         ---quant analysis under high low (risk spreed) 
         ---return open/close event to redis 

msgsklinetoredis :: ByteString -> Redis ()
msgsklinetoredis msg = do
    when (matchmsgfun msg == True ) $ do 
      void $ publish "skline:1" ( msg)
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
      message <- receiveData wc 
      --let msg = BL.fromStrict message
      --let test = A.decode msg :: Maybe Klinedata --Klinedata
      --stop <-getCurrentTime
      --SI.putStrLn (show (test))
      liftIO $ print (message)
      curtimestamp <- round . (* 1000) <$> getPOSIXTime
      res <- runRedis rc (replydo ) 
     
   -- add
      let orderitem = snd res
      let klineitem = fst res
      let cachetime = case klineitem of
            Left _ ->  "some error"
            Right v ->   (v!!0)
      let orderdet = case orderitem of
            Left _ ->  "some error"
            Right v ->   (v!!0)
      let replydomarray = DLT.splitOn "|" $ BLU.toString cachetime
      --liftIO $ print (replydomarray!!0)
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
         msgcacheandpingtempdo timediff message 
--         msgpingtempdo timediff message
         --void $ publish "cache" ("cache" <> "aaaaaaa")
         msgsklinetoredis message
         msganalysistoredis message
         msgordertempdo message orderdet
 -- let loop = do
 --         line <- T.getline
 --         unless (T.null line) $ do 
 --             print (line)
 --             let reline = line
 --             sendTextData connection (line)
 --             loop

 -- sendClose wc (B.pack "Bye!")

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
    
    liftIO $ print (msg)
    liftIO $ print ("))))))))))))))))))")
    let seperatemark = BLU.fromString ":::"
    let strturple = BL.fromStrict $ B.drop 3 $ snd $  B.breakSubstring seperatemark msg
    let restmsg = A.decode strturple :: Maybe WSevent  --Klinedata
    liftIO $ print (restmsg)
    let detdata = wsdata $ fromJust restmsg
    liftIO $ print (detdata)
    let dettype = wstream $ fromJust restmsg
    --liftIO $ print (dettype)
    when (dettype == "adausdt@kline_1m") $ do 
         let msgorigin = BLU.toString msg
         let msgitem = DLT.splitOn ":::" msgorigin 
         liftIO $ print (msgitem)
         let order = DLT.splitOn "|" $  (msgitem!!0)
         let klinemsg = msgitem !! 1
         liftIO $ print ("start take order")
         liftIO $ print (klinemsg)
         let orderquan = read (order !!4) :: Integer
         liftIO $ print (orderquan)
         kline <- getmsg  klinemsg 
         let curpr = read $ kclose kline :: Double
         let pr = 0.01 + curpr
         currtime <- getcurtimestamp 
         let curtime = fromInteger currtime ::Double
         liftIO $ print (curtime)
         conn <- connect defaultConnectInfo
         runRedis conn (proordertorediszset orderquan pr curtime)
         takeorder "BUY" orderquan pr 

    when (dettype /= "adausdt@kline_1m") $ do 
         let eventstr = fromJust $ detdata ^? key "e"
         let kline = case eventstr of 
                          DAT.String l -> l
         when (kline == "outboundAccountPosition") $ do 
            --get last record from redis ,than compare balance,if returnbalance-befbalance <= order quan then still under process,else set to End  
             
              liftIO $ print ("eeeee") 
         
         liftIO $ print $  (detdata ^? key "e") 
         liftIO $ print $  (detdata ^? key "E") 
         liftIO $ print $  (detdata ^? key "e") 
         --executionReport and outboundAccountPosition
        
   -- takeorder
   --change the state 
    --if type just = msg  and predication is qualified,then try get lock 
    --if type      = websocket account change/order token, release lock

getmsg :: String -> IO Klinedata
getmsg msg = do 
    let mmsg = BLU.fromString msg
    let mmmsg = BL.fromStrict mmsg
    let test = A.decode mmmsg :: Maybe Klinedata --Klinedata
    let kline = case test of 
                    Just l -> l
    return kline

addklinetoredis :: ByteString -> Redis ()
addklinetoredis msg  = do 
    let mmsg = BL.fromStrict msg
    let test = A.decode mmsg :: Maybe Klinedata --Klinedata
    let abykeystr = BLU.fromString "1m" 
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
    void $ zremrangebyrank abykeystr 50 1000
      --let msg = BL.fromStrict message
      --let test = A.decode msg :: Maybe Klinedata --Klinedata
      
sklineHandler :: RedisChannel -> ByteString -> IO ()
sklineHandler channel msg = do 
      conn <- connect defaultConnectInfo
      runRedis conn (addklinetoredis msg)
      debugtime

      
analysisHandler :: RedisChannel -> ByteString -> IO ()
analysisHandler channel msg = do 
      --conn <- connect defaultConnectInfo
      generatehlsheet msg
      debugtime

cacheHandler :: RedisChannel -> ByteString -> IO ()
cacheHandler channel msg = do 
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
      SI.hPutStrLn stderr $ "Saw msg: " ++ T.unpack (decodeUtf8 msg)
      debugtime


showChannels :: R.Connection -> IO ()
showChannels c = do
  resp :: Either Reply [ByteString] <- runRedis c $ sendRequest ["PUBSUB", "CHANNELS"]
  liftIO $ SI.hPutStrLn stderr $ "Current redis channels: " ++ show resp
  debugtime


