{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
module Redislib
    ( publishThread,
      onInitialComplete,
      handlerThread,
      msgHandler,
      pmsgHandler,
      showChannels
    ) where
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`

import Database.Redis as R
import Data.Monoid ((<>))
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
import Data.Aeson
import Data.Aeson.Lens
import qualified Data.ByteString.Char8 as B
import Data.Aeson.Types

-- | publish messages every 2 seconds to several channels
publishThread :: R.Connection -> NC.Connection -> IO ()
publishThread rc wc =  
  forever $ do
      message <- receiveData wc
      print (message )
      --print (typeOf(message))
      --print (Data.Aeson.decode message ::Maybe  WebsocketRsp)
      --traceShowM (Data.Aeson.decode message :: Maybe WebsocketRsp)
      --()
     -- let t = Data.Aeson.decode message :: Maybe Value 
     -- print(t) 
     -- -- turn msg to event,event use publish-subscribe to command handler
     -- -- return value
     -- -- use hredis to pub event to  channel to redis and correct the command
      runRedis rc $ do 
              void $ publish "foo" ("foo" <> message)
              void $ publish "bar" ("bar" <> message)
              void $ publish "baz:1" ("baz1" <> message)
              void $ publish "baz:2" ("baz2" <> message)
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

msgHandler :: ByteString -> IO ()
msgHandler msg = SI.hPutStrLn stderr $ "Saw msg: " ++ unpack (decodeUtf8 msg)

pmsgHandler :: RedisChannel -> ByteString -> IO ()
pmsgHandler channel msg = SI.hPutStrLn stderr $ "Saw pmsg: " ++ unpack (decodeUtf8 channel) ++ unpack (decodeUtf8 msg)

showChannels :: R.Connection -> IO ()
showChannels c = do
  resp :: Either Reply [ByteString] <- runRedis c $ sendRequest ["PUBSUB", "CHANNELS"]
  liftIO $ SI.hPutStrLn stderr $ "Current redis channels: " ++ show resp

