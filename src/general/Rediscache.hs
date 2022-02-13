{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`
module Rediscache (
   getSticksToCache,
   defintervallist,
   mseriesFromredis,
   parsetokline,
   liskeytoredis,
   getorderfromredis, 
   Ordervar (..),
--   liskeygetredis,
   initdict
) where

import Database.Redis as R
import Data.Map (Map)
import Data.String
import Data.List as DL
import qualified Data.ByteString as B
import qualified Data.ByteString.UTF8 as BL
import qualified Data.ByteString.Lazy as BLL
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Text (Text)
import Network.HTTP.Req
import qualified Data.Map as Map
import Data.Aeson as A
import Data.Aeson.Types
import Database.Redis
import GHC.Generics
import Data.Monoid ((<>))
import Control.Monad
import Control.Exception
import Control.Monad.Trans (liftIO)
import Httpstructure
import Data.List.Split as DLT
import Analysistructure as AS
import Order
import Globalvar
import Strategy
--import Control.Concurrent
--import System.IO as SI


data Ordervar = Ordervar {
  --orside :: String ,-- only "buy"  --if use coin or other future,then have two sides.now for spot only one side .for sell is definitely benefit .        
  osign :: Bool , --can open or not (for still have  order to complete or just start to take order,anti conconcurrent repeatly take order)
  orquant :: Integer ,--quantity          
  orbprice :: Double , --buyprice          
  orgrid :: Integer --grid level number          
} deriving (Show,Generic)

getorderfromredis :: Redis (Either Reply (Maybe BL.ByteString))
getorderfromredis = do 
   res <- get "order"
   return res

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
    liftIO $ print ("stick to cahce")
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
     let curitemt = read $ curitem !! 0  :: Integer
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
                   (True,True)   ->  (AS.Hlnode curitemt 0 curitemlp 0 "low" key)
                   (False,False) ->  (AS.Hlnode curitemt curitemhp 0 0 "high" key)
                   (False,True)  ->  (AS.Hlnode curitemt curitemhp curitemlp 0 "wbig" key)
                   (True,False)  ->  (AS.Hlnode curitemt 0 0 0 "wsmall" key)
     --liftIO $ print (res)
     return res

--gengridsheet


analysistrdo :: Either Reply [BL.ByteString] -> String -> IO [Double]
analysistrdo aa bb = do 
     let tdata = case aa of 
                     Right c -> c
     let hllist = [] :: [AS.Hlnode]
     let befitem = "undefined" -- traceback default trace first is unknow not high or low
     rehllist <- mapM ((\s ->  genehighlowsheet s tdata bb) :: Int -> IO AS.Hlnode ) [0..13] :: IO [AS.Hlnode] 
     liftIO $ print ("yyyyyyyyyyyyyy")
     --liftIO $ print (rehllist)
     let reslist = [(xlist!!x)|x<-[1..(length xlist)-2],((stype $ xlist!!(x-1)) /= (stype $ xlist!!x)) && ((stype $ xlist!!x) /= "wsmall") ] where xlist = rehllist
     let highsheet = [(hprice $ xlist!!x)| x<-[1..(length xlist)-2],((hprice $ xlist!!x) > 0.1)  ] where xlist = rehllist
     let lowsheet = [(lprice $ xlist!!x)| x<-[1..(length xlist)-2] ,((lprice $ xlist!!x) > 0.1)  ] where xlist = rehllist
     let highgrid = maximum highsheet
     let lowgrid = minimum lowsheet
     let diff = (highgrid-lowgrid)/3 
     -- 1day earn : 0.02*2*24/6 
     --if current price in range (lowgrid+diff,highgrid-diff),can open,other forbiden
     --
     

     liftIO $ print (highgrid)
     liftIO $ print (lowgrid)
     --gengridsheet
  -- put position and price grid to the sheet
  -- store to redis 
     liftIO $ print (reslist)
     liftIO $ print ("yyyyyyyyyyyyyy")
     return [lowgrid,highgrid]

parsetokline :: BL.ByteString -> IO Klinedata
parsetokline msg = do 
     let mmsg = BLL.fromStrict msg
     let test = A.decode mmsg :: Maybe Klinedata --Klinedata
     let abykeystr = BL.fromString "1m" 
     let kline = case test of 
                     Just l -> l
     return kline

analysisdo :: [Either Reply [BL.ByteString]] -> IO [[Double]]
analysisdo aim  = do 
     hlsheet <-  zipWithM analysistrdo aim defintervallist
     return hlsheet
     

mserieFromredis :: String -> Redis (Either Reply [BL.ByteString])
mserieFromredis klinename = do  
     --get kline and ada position,usdt position
     let bklinename = BL.fromString klinename
     res <- zrange bklinename 0 15
     return res
              
mseriesFromredis :: R.Connection -> BL.ByteString -> IO ()
mseriesFromredis conn msg = do
     res <- runRedis conn $ do
                  mapM mserieFromredis defintervallist 
     hlsheet <- analysisdo res 
     kline <- parsetokline msg
     --liftIO $ print (hlsheet)
     let mconlist = (DL.sort $ concat hlsheet) ++ [1000]
     --liftIO $ print (mconlist)
     let lenmcon = length mconlist
     let mconlistl = [mconlist!!i |i<-[0..(lenmcon-2)],(mconlist!!(i+1)-mconlist!!i)>=0.006]
     --let aimlist = [i|i <- x,x <- hlsheet]
     --liftIO $ print (mconlistl)
     let dcp = read $ kclose kline :: Double
     let interprl = [(x,y)|x<-defintervallist,let y= dcp]
     res <- zipWithM saferegionrule interprl hlsheet
     let sumres = sum res
     when (sumres > 0) $ do
          curtimestampi <- getcurtimestamp
          let curtimestamp = fromInteger curtimestampi :: Double
          runRedis conn $ do
             preordertorediszset sumres dcp  curtimestamp
     --genposgrid hlsheet dcp
  --write order command to zset
     liftIO $ print ("ssss")
     

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
