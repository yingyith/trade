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
import qualified Data.ByteString as B
import qualified Data.ByteString.UTF8 as BL
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
defintervallist :: [String]
defintervallist = ["5m","15m","1h","4h"] 

getSticksToCache :: IO ()
getSticksToCache = do 
    tt <- mapM parsekline defintervallist
    --liftIO $ print (tt)
    conn <- R.connect R.defaultConnectInfo
    initdict tt conn

hsticklistToredis :: [HStick] -> R.Connection -> IO [()]
hsticklistToredis a conn =
    runRedis conn $ do
        mapM hstickToredis a 

hstickToredis :: HStick -> Redis ()
hstickToredis a  = do
    let dst = st a
    let dop = op a
    let dcp = cp a
    let dhp = hp a
    let dlp = lp a
    let ddst = fromInteger dst :: Double
    let sst = BL.fromString $ show dst
    let sop = BL.fromString dop
    let scp = BL.fromString dcp
    let shp = BL.fromString dhp
    let slp = BL.fromString dlp
    let abykeystr = BL.fromString  ("5min"++(show dst))
    void $ zadd abykeystr [(ddst,abykeystr)]
    


initdict :: [DpairMserie] -> R.Connection -> IO ()
initdict rsp conn = do 
  --parse rsp json
  -- for i in response ,every elem add to key rlist 
  forM_ rsp $ \s -> do 
     --case s of 
     --    Nothing -> Nothing
     --    Just a -> liftIO $ print (a)
     let currms = getmsfrpair s
     let currinterval = getintervalfrpair s
     let tdata = case currms of 
                      Just b -> b
     liftIO $ print (tdata)
     let ttdata = getmsilist tdata
     liftIO $ print (ttdata)
     hsticklistToredis ttdata conn 
     
   --get from web api and update
   
--initrdcit :: rdict->rdict
   --get from web api and update
