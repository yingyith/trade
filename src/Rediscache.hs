{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`
module Rediscache (
   sticks,
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
--import Control.Concurrent
--import System.IO as SI

-- update redis cache kline dict
--init kline dict
-- 1min line update in memory every stick,other update in memory 


sticks :: Map.Map String [a]
sticks = Map.fromList [("1min",[]),("5min",[]),("15min",[]),("60min",[]),("4hour",[]),("12hour",[]),("3day",[]),("1week",[])]

initdict :: [ JsonResponse Value] -> R.Connection -> IO ()
initdict rsp conn = do 
  --parse rsp json
  -- for i in response ,every elem add to key rlist 
  runRedis conn $ do
     void $ set "world" "world"
   --get from web api and update
   
--initrdcit :: rdict->rdict
   --get from web api and update
