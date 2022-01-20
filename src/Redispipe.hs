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
    ) where
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`

import Database.Redis as R
import Data.Monoid ((<>))
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
import Httpstructure
import Rediscache

--import Klinedata (kname) 
-- | publish messages every 2 seconds to several channels
replydo :: Redis (Either Reply  [ByteString])
replydo = do
        let s = "5m"
        let akey = BLU.fromString s
        item <- zrange akey 14 15 
        return item
       -- let res = case compare (curtimestamp - replydores) 6000 of 
       --             LT -> "True"
       --             EQ -> "True"
       --             GT -> "False"
       -- return res
            --Right v -> return  (fromMaybe "try" v)

publishThread :: R.Connection -> NC.Connection -> IO ()
publishThread rc wc =  
  forever $ do
      message <- receiveData wc 
      let msg = BL.fromStrict message
      print (msg)
      let test = A.decode msg :: Maybe Klinedata --Klinedata
      SI.putStrLn (show (test))
      curtimestamp <- round . (* 1000) <$> getPOSIXTime
      res <- runRedis rc (replydo ) 
      let cachetime = case res of
            Left _ ->  "some error"
            Right v ->   (v!!0)
      let replydomarray = DLT.splitOn "|" $ BLU.toString cachetime
      liftIO $ print (replydomarray!!0)
      let replydores = (read (replydomarray !! 0)) :: Integer
      liftIO $ print (replydores)
  -----------------------------
  --check curtime need to update



      --get the data of kline cache ,check the invalid key number and update these
              
      --print (ktype test)
      --decide which event now is
      --1.check redis cache ,if cache valid time pass ,then send update command,detail two,one for stick update,one for put listenkey every 30min
      --2.check all open and close condition ,if match ,send open/close command
      --dispatch event to detail command
      runRedis rc $ do 
              void $ publish "foo" ("foo" <> message)
              void $ publish "bar" ("bar" <> message)
              void $ publish "cacheupdate:1" ("baz1" <> message)
              void $ publish "cacheupdate:2" ("baz2" <> message)
              liftIO $ threadDelay $ 2*1000*1000 -- 2 seconds
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

cacheHandler :: RedisChannel -> ByteString -> IO ()
cacheHandler channel msg = SI.hPutStrLn stderr $ "Saw pmsg: " ++ unpack (decodeUtf8 channel) ++ unpack (decodeUtf8 msg)

listenkeyHandler :: RedisChannel-> ByteString -> IO ()
listenkeyHandler channel msg = SI.hPutStrLn stderr $ "Saw msg: " ++ unpack (decodeUtf8 msg)

showChannels :: R.Connection -> IO ()
showChannels c = do
  resp :: Either Reply [ByteString] <- runRedis c $ sendRequest ["PUBSUB", "CHANNELS"]
  liftIO $ SI.hPutStrLn stderr $ "Current redis channels: " ++ show resp

