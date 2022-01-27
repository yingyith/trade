{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`
module Rediscache (
   getSticksToCache,
   defintervallist,
   mseriesFromredis,
   liskeytoredis,
--   liskeygetredis,
   initdict
) where

import Database.Redis as R
import Data.Map (Map)
import Data.String
import Data.List
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
import Data.List.Split as DLT
import Analysistructure as AS
--import Control.Concurrent
--import System.IO as SI

-- update redis cache kline dict
--init kline dict
-- 1min line update in memory every stick,other update in memory 
defintervallist :: [String]
defintervallist = ["5m","15m","1h","4h","12h","3d"] 

liskeytoredis :: String -> Redis ()
liskeytoredis a = do 
    --string to bytestring
   let value = BL.fromString a
   let key = BL.fromString "liskey"
   void $ del [key] 
   void $ set key value

---liskeygetredis  ::  Redis ([Maybe BL.ByteString])
---liskeygetredis  = do 
---    --string to bytestring
---   let key = BL.fromString "liskey"
---   value <- get key
---   return value

getSticksToCache :: IO ()
getSticksToCache = do 
    tt <- mapM parsekline defintervallist
    --liftIO $ print (tt)
    conn <- R.connect R.defaultConnectInfo
    initdict tt conn

mseriesToredis :: [DpairMserie] -> R.Connection -> IO ()
mseriesToredis a conn = do
    void $ runRedis conn $ do
        --mapM hstickToredis a 
                 zipWithM hsticklistToredis  a  defintervallist 


--pinghandledo :: Maybe BL.ByteString -> IO ()
--pinghandledo a  =  runReq defaultHttpConfig $ do
genehighlowsheet :: Int -> [BL.ByteString] -> String -> IO AS.Hlnode
genehighlowsheet index hl key = do 
             let curitemstr = BL.toString $ hl !! index
             let nextitemstr= BL.toString $ hl !! (index+1)
             let curitem = DLT.splitOn "|" curitemstr
             let nextitem = DLT.splitOn "|" nextitemstr
             let curitemop = read $ curitem !! 1  :: Double
             let curitemhp = read $ curitem !! 2  :: Double
             let curitemlp = read $ curitem !! 3  :: Double
             let curitemcp = read $ curitem !! 4  :: Double
             let nextitemop = read $ nextitem !! 1  :: Double
             let nextitemhp = read $ nextitem !! 2  :: Double
             let nextitemlp = read $ nextitem !! 3  :: Double
             let nextitemcp = read $ nextitem !! 4  :: Double
             let hpointpredication = (curitemhp - nextitemhp) <= 0
             let lpointpredication = (curitemlp - nextitemlp) <= 0
             let predication = (hpointpredication,lpointpredication)
             let res = case predication of 
                           (True,True)   ->  (AS.Hlnode 0 curitemlp 0 "low" key)
                           (False,False) ->  (AS.Hlnode curitemhp 0 0 "high" key)
                           (False,True)  ->  (AS.Hlnode curitemhp curitemlp 0 "wbig" key)
                           (True,False)  ->  (AS.Hlnode 0 0 0 "wsmall" key)
             --liftIO $ print (res)
             return res

--gengridsheet


analysistrdo :: Either Reply [BL.ByteString] -> String -> IO [AS.Hlnode]
analysistrdo aa bb = do 
         let tdata = case aa of 
                         Right c -> c
         let hllist = [] :: [AS.Hlnode]
         let befitem = "undefined" -- traceback default trace first is unknow not high or low
         rehllist <- mapM ((\s ->  genehighlowsheet s tdata bb) :: Int -> IO AS.Hlnode ) [0..13] :: IO [AS.Hlnode] 
         liftIO $ print ("yyyyyyyyyyyyyy")
         --liftIO $ print (rehllist)
         let reslist = [(xlist!!x)|x<-[0..(length xlist)-2],(stype $ xlist!!x) /= (stype $ xlist!!(x+1)) && ((stype $ xlist!!x) /= "wsmall") ] where xlist = rehllist
         --gengridsheet
         liftIO $ print (reslist)
         liftIO $ print ("yyyyyyyyyyyyyy")
         return rehllist

analysisdo :: [Either Reply [BL.ByteString]] -> IO [[AS.Hlnode]]
analysisdo aim = do 
     zipWithM analysistrdo aim defintervallist
     

mserieFromredis :: String -> Redis (Either Reply [BL.ByteString])
mserieFromredis klinename = do  
          let bklinename = BL.fromString klinename
          res <- zrange bklinename 0 15
          return res
              

mseriesFromredis :: R.Connection -> IO ()
mseriesFromredis conn = do
     res <- runRedis conn $ do
                  mapM mserieFromredis defintervallist 
     analysisdo res
     --let tdata = case res of 
     --              Just b -> b
     
     liftIO $ print ("sss!!!!!!!!!!!!") 
     liftIO $ print ("sss") 

hsticklistToredis :: DpairMserie -> String -> Redis ()
hsticklistToredis hst  akey   = do
  let currms = getmsfrpair hst
  let currinterval = getintervalfrpair hst
  let tdata = case currms of 
                   Just b -> b
  --liftIO $ print (tdata)
  let ttdata = getmsilist tdata
  let abykeystr = BL.fromString akey
  void $ zremrangebyrank abykeystr 0 1000
  forM_ ttdata $ \s -> do 
    let dst = st s 
    let dop = op s 
    let dcp = cp s 
    let dhp = hp s 
    let dlp = lp s 
    let ddst = fromInteger dst :: Double
    let sst = BL.fromString $ show dst
    let sop = BL.fromString dop
    let scp = BL.fromString dcp
    let shp = BL.fromString dhp
    let slp = BL.fromString dlp
    let abyvaluestr = BL.fromString  $ intercalate "|" [show dst,dop,dcp,dhp,dlp]
    void $ zadd abykeystr [(-ddst,abyvaluestr)]
    


initdict :: [DpairMserie] -> R.Connection -> IO ()
initdict rsp conn = do 
  --parse rsp json
  -- for i in response ,every elem add to key rlist 
  --forM_ rsp $ \s -> do 
  --   --case s of 
  --   --    Nothing -> Nothing
  --   --    Just a -> liftIO $ print (a)
  --   let currms = getmsfrpair s
  --   let currinterval = getintervalfrpair s
  --   let tdata = case currms of 
  --                    Just b -> b
  --   --liftIO $ print (tdata)
  --   let ttdata = getmsilist tdata
  --   liftIO $ print (ttdata)
     mseriesToredis rsp conn 
     
   --get from web api and update
   
--initrdcit :: rdict->rdict
   --get from web api and update
