{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
module Redispipe
    ( publishThread,
      onInitialComplete,
      handlerThread,
      commandHandler,
      msgHandler,
      pmsgHandler,
      showChannels,
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
import Data.Aeson as A
import Data.Aeson.Lens
import qualified Data.ByteString.Char8 as B
import qualified Data.ByteString.Lazy as BL
import Data.Aeson.Types
import Httpstructure
-- | publish messages every 2 seconds to several channels
publishThread :: R.Connection -> NC.Connection -> IO ()
publishThread rc wc =  
  forever $ do
      message <- receiveData wc 
      let msg = BL.fromStrict message
      print (msg)
      let test = A.decode msg :: Maybe Klinedata
      SI.putStrLn (show (test))
      print ("------------------")
      let message = "sss"
      --if type == account  ------sync ===> event sync 
      --if type == stick  
         -- add pre judge condition strategy process
         --if openlong condition ---- open long ==> event1 (openlong)
         --if openshort condition ---- open long ==> event2 (openlong)
         --if closelong condition ---- open long ==> event3 (openlong)
         --if closeshort condition ---- open long ==> event4 (openlong)
      --
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
--- do command detail operation here
  -- multi command operation now
commandHandler :: ByteString -> IO ()
commandHandler msg = SI.hPutStrLn stderr $ "Saw msg: " ++ unpack (decodeUtf8 msg)

msgHandler :: ByteString -> IO ()
msgHandler msg = SI.hPutStrLn stderr $ "Saw msg: " ++ unpack (decodeUtf8 msg)

pmsgHandler :: RedisChannel -> ByteString -> IO ()
pmsgHandler channel msg = SI.hPutStrLn stderr $ "Saw pmsg: " ++ unpack (decodeUtf8 channel) ++ unpack (decodeUtf8 msg)

showChannels :: R.Connection -> IO ()
showChannels c = do
  resp :: Either Reply [ByteString] <- runRedis c $ sendRequest ["PUBSUB", "CHANNELS"]
  liftIO $ SI.hPutStrLn stderr $ "Current redis channels: " ++ show resp

