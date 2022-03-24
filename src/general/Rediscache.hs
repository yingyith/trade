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
   gettimefromredis, 
   getspotbaltoredis,
   setkvfromredis,
   getmsgfromstr,
   getbalfromredis,
   Ordervar (..),
--   liskeygetredis,
   initdict
) where

import Database.Redis as R
--import Data.Map (Map)
import Data.String
import Data.List as DL
import qualified Data.ByteString as B
import qualified Data.ByteString.UTF8 as BL
import qualified Data.ByteString.Lazy as BLL
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Text (Text)
import Data.Either
import Data.Maybe
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
import Sndsrule
--import Control.Concurrent
--import System.IO as SI


data Ordervar = Ordervar {
  --orside :: String ,-- only "buy"  --if use coin or other future,then have two sides.now for spot only one side .for sell is definitely benefit .        
  osign :: Bool , --can open or not (for still have  order to complete or just start to take order,anti conconcurrent repeatly take order)
  orquant :: Integer ,--quantity          
  orbprice :: Double , --buyprice          
  orgrid :: Integer --grid level number          
} deriving (Show,Generic)

getorderfromredis :: Redis (Either Reply [BL.ByteString])
getorderfromredis = do 
   let bklinename = BL.fromString orderkey
   res <- zrange bklinename 0 0
   return res

gettimefromredis :: Redis (Either Reply (Maybe BL.ByteString))
gettimefromredis = do 
   let timekeybs = BL.fromString timekey
   res <- get timekeybs
   return res

getbalfromredis :: Redis (Either Reply (Maybe BL.ByteString),Either Reply (Maybe BL.ByteString))
getbalfromredis = do 
   let adaname = BL.fromString adakey
   adab <- get adaname 
   let usdtname = BL.fromString usdtkey
   usdtb <- get usdtname 
   return (adab,usdtb)

setkvfromredis :: String -> String -> Redis ()
setkvfromredis key value = do 
   let keybs = BL.fromString key
   let valuebs = BL.fromString value
   void $ set keybs valuebs

liskeytoredis :: String -> Integer -> Redis ()
liskeytoredis a b = do 
    --string to bytestring
   let value = BL.fromString a
   let key = BL.fromString liskey
   let badakey = BL.fromString adakey
   let busdtkey = BL.fromString usdtkey
   let timekeyy = BL.fromString timekey
   let timevalue = BL.fromString $ show b
   void $ set timekeyy timevalue
   --init curtime to redis ,let retry failure count it .
   void $ del [key] 
   void $ del [badakey] 
   void $ del [busdtkey] 
   void $ set key value
   void $ zremrangebyrank (BL.fromString orderkey) 0 2000
   void $ zremrangebyrank (BL.fromString secondkey) 0 2000
   let abyvaluestr = BL.fromString  $ intercalate "|" ["start","Buy","0","0","20","1","5"]
   void $ zadd (BL.fromString orderkey) [(0,abyvaluestr)]
   ---delete other key


---liskeygetredis  ::  Redis ([Maybe BL.ByteString])
---liskeygetredis  = do 
---    --string to bytestring
---   let key = BL.fromString "liskey"
---   value <- get key
---   return value
getspotbaltoredis :: R.Connection ->  IO ()
getspotbaltoredis conn = do 
    bal <- getspotbalance 
    let adabal = fst bal
    let usdtbal = snd bal
    void $ runRedis conn $ do
              let adavalue = BL.fromString $ show adabal
              let usdtvalue = BL.fromString $  show usdtbal
              let akey = BL.fromString adakey
              let ukey = BL.fromString usdtkey
              void $ set akey adavalue
              void $ set ukey usdtvalue

getSticksToCache :: R.Connection -> IO ()
getSticksToCache conn = do 
    tt <- mapM parsekline defintervallist
    initdict tt conn

mseriesToredis :: [DpairMserie] -> R.Connection -> IO (Either Reply [BL.ByteString])
mseriesToredis a conn = do
    runRedis conn $ do
       zipWithM hsticklistToredis  a  defintervallist 
       zrange (BL.fromString secondkey)  0 secondstick  



analysistrdo :: Either Reply [BL.ByteString] -> (String,Double) -> IO ((Int,Double),(String,Int))
analysistrdo aa bb = do 
     let tdata = fromRight []  aa 
     let interval = fst bb
     let curpr = snd bb
     let hllist = [] :: [AS.Hlnode]
     let befitem = "undefined" -- traceback default trace first is unknow not high or low
    -- liftIO $ print ("tdata is ---------------------")
     --liftIO $ print (tdata)
     let lentdata = length tdata
     rehllist <- mapM ((\s ->  genehighlowsheet s tdata interval) :: Int -> IO AS.Hlnode ) [0..(lentdata-2)] :: IO [AS.Hlnode] 
     --liftIO $ print (rehllist)
     --liftIO $ print ("hlsheet 1--------------------------")
  --   let reslist = [(xlist!!x)|x<-[1..(length xlist)-2],((stype $ xlist!!(x-1)) /= (stype $ xlist!!x)) && ((stype $ xlist!!x) /= "wsmall") ] where xlist = rehllist
  --  -- liftIO $ print ("hlsheet 2--------------------------")
  --   let highsheet = [(hprice $ xlist!!x)| x<-[1..(length xlist)-2],((hprice $ xlist!!x) > 0.1)  ] where xlist = rehllist
  --   let lowsheet = [(lprice $ xlist!!x)| x<-[1..(length xlist)-2] ,((lprice $ xlist!!x) > 0.1)  ] where xlist = rehllist
  --   let highgrid = maximum highsheet
  --   let lowgrid = minimum lowsheet
  --   let diff = (highgrid-lowgrid)/3 
     quantylist <- minrule rehllist curpr interval 

     return quantylist

parsetokline :: BL.ByteString -> IO Klinedata
parsetokline msg = do 
     let mmsg = BLL.fromStrict msg
    -- liftIO $ print (msg)
     
     let test = A.decode mmsg :: Maybe Klinedata --Klinedata
     case test of 
         Nothing -> do liftIO $ print (msg)
         _ -> return ()
         
     let kline = fromJust test
     return kline

analysismindo :: [Either Reply [BL.ByteString]] -> Double -> IO [((Int,Double),(String,Int))]
analysismindo aim curpr = do 
     let aimlist = [(x,y)| x<-defintervallist] where y=curpr 
     --liftIO $ print ("analysisdi--------------------ai")
     --liftIO $ print (aim)
     hlsheet <-  zipWithM analysistrdo aim aimlist

     --liftIO $ print (hlsheet)
     return hlsheet

getmsgfromstr :: String -> IO Klinedata
getmsgfromstr msg = do 
    let mmsg = BL.fromString msg
    liftIO $ print ("----------++++++++----------")
    res <- parsetokline mmsg
    return res

getsndkline :: Either Reply [BL.ByteString] -> IO [Klinedata] 
getsndkline aim  = do 
     let res = fromRight []  aim  
     liftIO $ print (aim,length aim)
     klines <- mapM parsetokline res
     --liftIO $ print (klines)
     return klines
     

mserieFromredis :: String -> Redis (Either Reply [BL.ByteString])
mserieFromredis klinename = do  
     --get kline and ada position,usdt position
     let bklinename = BL.fromString klinename
     res <- zrange bklinename 0 21
     return res

getdiffintervalflow :: Redis ([Either Reply [BL.ByteString]],
                            Either Reply [BL.ByteString]) 
getdiffintervalflow = do 
     fisar <- mapM mserieFromredis defintervallist 
     sndar <- zrange (BL.fromString secondkey)  0 secondstick  
     return (fisar,sndar)
     

mseriesFromredis :: R.Connection -> BL.ByteString -> IO ()
mseriesFromredis conn msg = do
     res <- runRedis conn (getdiffintervalflow)
     --liftIO $ print ("mseiries")
     kline <- parsetokline msg
     let dcp = read $ kclose kline :: Double
     --liftIO $ print ("start analysis min --------------------------------------")
     bigintervall <- analysismindo (fst res ) dcp
     --liftIO $ print bigintervall
     biginterval <- crossminstra bigintervall
     --liftIO $ print ("start analysis snd --------------------------------------")
     sndinterval <- getsndkline (snd res) 
     timecur <- getcurtimestamp
     secondnum <- secondrule sndinterval
     --liftIO $ print ("start pre or cpre --------------------------------------")
     --liftIO $  print ("++--",timecur,biginterval,secondnum)
     let sumres = biginterval + secondnum
     curtimestampi <- getcurtimestamp
     runRedis conn $ do
        preorcpreordertorediszset sumres dcp  curtimestampi
     --genposgrid hlsheet dcp
  --write order command to zset
     

hsticklistToredis :: DpairMserie -> String -> Redis ()
hsticklistToredis hst  akey   = do
  let currms = getmsfrpair hst
  let currinterval = getintervalfrpair hst
  let tdata = case currms of 
                   Just b -> b
  --liftIO $ print (tdata)
  let ttdata = getmsilist tdata
  let abykeystr = BL.fromString akey
  void $ zremrangebyrank abykeystr 1 1000
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
     void $ mseriesToredis rsp conn 
     
   --get from web api and update
   
--initrdcit :: rdict->rdict
   --get from web api and update
