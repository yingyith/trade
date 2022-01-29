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
import Network.WebSockets (ClientApp, receiveData, sendClose, sendTextData)
import Network.WebSockets.Connection as NC
import Control.Concurrent.Async
import Data.Text as T
import Data.Text.IO as T
import Data.ByteString (ByteString)
import Data.Text.Encoding
import System.IO as SI
import Data.Aeson as A
import Data.Aeson.Lens
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.List.Split as DLT
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.UTF8 as BLU
import qualified Data.ByteString.Lazy as BL
import Data.Aeson.Types
import Data.List as DL
import Httpstructure
import Rediscache

--import Klinedata (kname) 
-- | publish messages every 2 seconds to several channels
replydo :: Redis (Either Reply  [ByteString])
replydo = do
        let s = "5m"
        let akey = BLU.fromString s
        item <- zrange akey 0 1 
        return item
       -- let res = case compare (curtimestamp - replydores) 6000 of 
       --             LT -> "True"
       --             EQ -> "True"
       --             GT -> "False"
       -- return res
            --Right v -> return  (fromMaybe "try" v)
            
iscacheinvalid    ::         Bool  
iscacheinvalid = True
ispinginvalid     ::         Bool  
ispinginvalid = True
isstrategyinvalid ::         Bool  
isstrategyinvalid = True
--the predications of rule system 


msgcachetempdo :: Integer -> ByteString -> Redis ()
msgcachetempdo a msg = do
        case compare a 300000 of -- 300000= 5min
        --case compare a 300000 of -- 300000= 5min
            GT -> 
              void $ publish "cache:1" ("cache" <> msg)
            EQ ->
              return ()
            LT ->
              return ()
          

msgpingtempdo :: Integer -> ByteString -> Redis ()
msgpingtempdo a msg = do
        case compare a 600000 of -- 600000= 10min
            GT -> 
              void $ publish "listenkey:1" ("listenkey" <> msg)
            EQ ->
              return ()
            LT ->
              return ()

msgordertempdo :: Redis ()
msgordertempdo =  return ()

generatehlsheet :: ByteString -> IO ()
generatehlsheet msg = do 
         conn <- connect defaultConnectInfo
         liftIO $ print ("do analysis!")
         mseriesFromredis conn msg--get all mseries from redis 
         ---generate high low point spreet
         ---quant analysis under high low (risk spreed) 
         ---return open/close event to redis 

msgsklinetoredis :: ByteString -> Redis ()
msgsklinetoredis msg = do
      void $ publish "skline:1" ( msg)
      --let test = A.decode msg :: Maybe Klinedata --Klinedata
      --liftIO $ print (test)
      -- store to kline seconds in  redis key as  1m 
msganalysistoredis :: ByteString -> Redis ()
msganalysistoredis msg = do
      liftIO $ print ("analysis to redis")
      void $ publish "analysis:1" ( msg)

getliskeyfromredis :: Redis ()
getliskeyfromredis =  return ()

publishThread :: R.Connection -> NC.Connection -> IO ()
publishThread rc wc =  
  forever $ do
      liftIO $ print ("++++++++++++")
      message <- receiveData wc 
      --let msg = BL.fromStrict message
      liftIO $ print ("++++++++++++")
      liftIO $ print (message)
      --let test = A.decode msg :: Maybe Klinedata --Klinedata
      --stop <-getCurrentTime
      --liftIO $ print $ diffUTCTime stop start
      --SI.putStrLn (show (test))
      curtimestamp <- round . (* 1000) <$> getPOSIXTime
      res <- runRedis rc (replydo ) 
      let cachetime = case res of
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
         msgcachetempdo timediff message 
         msgpingtempdo timediff message
         --void $ publish "cache" ("cache" <> "aaaaaaa")
         msgordertempdo
         msgsklinetoredis message
         msganalysistoredis message
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

handlerThread :: R.Connection -> PubSubController -> IO ()
handlerThread conn ctrl = forever $
       pubSubForever conn ctrl onInitialComplete
         `catch` (\(e :: SomeException) -> do
           SI.hPutStrLn stderr $ "Got error: " ++ show e
           threadDelay $ 50*1000)
--- do command detail operation here
  -- multi command operation now
--listenkeyHandler :: ByteString -> IO ()
--listenkeyHandler msg = SI.hPutStrLn stderr $ "Saw msg: " ++ unpack (decodeUtf8 msg)

opclHandler :: ByteString -> IO ()
opclHandler msg = SI.hPutStrLn stderr $ "Saw msg: " ++ unpack (decodeUtf8 msg)


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
      
analysisHandler :: RedisChannel -> ByteString -> IO ()
analysisHandler channel msg = do 
      --conn <- connect defaultConnectInfo
      generatehlsheet msg

cacheHandler :: RedisChannel -> ByteString -> IO ()
cacheHandler channel msg = do 
      getSticksToCache
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
      SI.hPutStrLn stderr $ "Saw msg: " ++ unpack (decodeUtf8 msg)

showChannels :: R.Connection -> IO ()
showChannels c = do
  resp :: Either Reply [ByteString] <- runRedis c $ sendRequest ["PUBSUB", "CHANNELS"]
  liftIO $ SI.hPutStrLn stderr $ "Current redis channels: " ++ show resp

