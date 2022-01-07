{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`
module Rediscache (
   getSticksToCache,
   initdict
) where

import Database.Redis as R
import Data.Map (Map)
import Data.String
import Data.ByteString
import Data.Text (Text)
import Network.HTTP.Req
import qualified Data.Map as Map
import Data.Aeson.Types
import Database.Redis
import Data.Monoid ((<>))
import Control.Monad
import Control.Exception
import Control.Monad.Trans (liftIO)
import Httpstructure
--import Control.Concurrent
--import System.IO as SI

-- update redis cache kline dict
--init kline dict
-- 1min line update in memory every stick,other update in memory 

getSticksToCache :: IO ()
getSticksToCache = do 
    tt <- mapM parsekline ["5m","15m","1h","4h"] 
    --liftIO $ print (tt)
    conn <- R.connect R.defaultConnectInfo
    initdict tt conn


initdict :: [ Maybe Mseries ] -> R.Connection -> IO ()
initdict rsp conn = do 
  --parse rsp json
  -- for i in response ,every elem add to key rlist 
  forM_ rsp $ \s -> do 
     --case s of 
     --    Nothing -> Nothing
     --    Just a -> liftIO $ print (a)
     let tdata = case s of 
                      Just b -> b
     liftIO $ print (s)
     runRedis conn $ do
        void $ set "world" "world"
   --get from web api and update
   
--initrdcit :: rdict->rdict
   --get from web api and update
