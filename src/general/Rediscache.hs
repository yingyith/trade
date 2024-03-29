{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`
module Rediscache (
   minSticksToCache,
   defintervallist,
   anlytoBuy,
   parsetokline,
   liskeytoredis,
   getorderfromredis, 
   gettimefromredis, 
   getspotbaltoredis,
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
import Data.ByteString.Char8 as  BC
import qualified Data.ByteString.UTF8 as BL
import qualified Data.ByteString.Lazy as BLL
import qualified Data.ByteString.Lazy.UTF8 as BLU
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Time.LocalTime
import Data.Time.Format
import Data.Text (Text)
import Data.Either
import Data.Maybe
import Network.HTTP.Req
import qualified Data.Map as Map
import Data.Aeson as A
import Data.Aeson.Types
import Database.Redis
import GHC.Generics
import GHC.Conc
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
import Logger
import System.Log.Logger 
import System.Log.Handler (setFormatter)
import System.Log.Handler.Syslog
import System.Log.Handler.Simple
import System.Log.Formatter
import Control.Concurrent.STM
import Colog (LogAction,logByteStringStdout)
import Data.Time.Format.ISO8601
import Data.Time.Clock.POSIX
import Redisutils
import Buslib
import Lib
import System.IO as SI
import Control.Concurrent.STM.TVar
import Events

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
   let abyvaluestr = BL.fromString  $ DL.intercalate "|" ["start","BUY","0","0","20","1","0","0","11"]
   void $ zadd (BL.fromString orderkey) [(0,abyvaluestr)]
   ---delete other key


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

minSticksToCache :: R.Connection -> IO ()
minSticksToCache conn = do 
    tt <- mapM parsekline defintervallist
    initdict tt conn

mseriesToredis :: [DpairMserie] -> R.Connection -> IO (Either Reply [BL.ByteString])
mseriesToredis a conn = do
    runRedis conn $ do
       zipWithM hsticklistToredis  a  defintervallist 
       zrange (BL.fromString secondkey)  0 secondstick  



analysistrdo :: Either Reply [BL.ByteString] -> (String,Double) -> IO (((Int,(Double,Double)),(String,Int)),[Hlnode])
analysistrdo aa bb = do 
     let tdata = fromRight []  aa 
     let interval = fst bb
     let curpr = snd bb
     let hllist = [] :: [AS.Hlnode]
     let befitem = "undefined" -- traceback default trace first is unknow not high or low
     let lentdata = DL.length tdata
     rehllist <- mapM ((\s ->  genehighlowsheet s tdata interval) :: Int -> IO AS.Hlnode ) [0..(lentdata-2)] :: IO [AS.Hlnode] 
     quantylist <- minrule rehllist curpr interval 

     return (quantylist,rehllist)

parsetokline :: BL.ByteString -> IO Klinedata
parsetokline msg = do 
     let mmsg = BLL.fromStrict msg
     let test = A.decode mmsg :: Maybe Klinedata --Klinedata
     case test of 
        Nothing -> do
                      logact logByteStringStdout $ BC.pack  (show msg)
        _       -> return ()
         
     let kline = fromJust test
     return kline

analysismindo :: [Either Reply [BL.ByteString]] -> Double -> IO [(((Int,(Double,Double)),(String,Int)),[Hlnode])]
analysismindo aim curpr = do 
     let aimlist = [(x,y)| x<-defintervallist] where y=curpr 
     hlsheet <-  zipWithM analysistrdo aim aimlist
     return hlsheet

getmsgfromstr :: String -> IO Klinedata
getmsgfromstr msg = do 
    let mmsg = BL.fromString msg
    res <- parsetokline mmsg
    return res

getsndkline :: Either Reply [BL.ByteString] -> IO [Klinedata] 
getsndkline aim  = do 
     let resl = fromRight [] aim
     logact logByteStringStdout $ BC.pack  (show $ DL.length resl )
     case (toInteger $ DL.length $ resl) of 
         x|x < secondstick -> return []
         _                 -> do 
                                 let res = DL.take 30  resl 
                                 klines <- mapM parsetokline res
                                 return klines
     

mserieFromredis :: String -> Redis (Either Reply [BL.ByteString])
mserieFromredis klinename = do  
     let bklinename = BL.fromString klinename
     res <- zrange bklinename 0 21
     return res

getdiffintervalflow :: Redis ([Either Reply [BL.ByteString]],
                               Either Reply [BL.ByteString]) 
getdiffintervalflow = do 
     fisar <- mapM mserieFromredis defintervallist 
     sndar <- zrange (BL.fromString secondkey)  0 secondstick  
     return (fisar,sndar)
     

anlytoBuy ::  TBQueue Opevent ->  R.Connection -> BL.ByteString ->  (TVar AS.Depthset)-> (TVar Curorder) -> (TVar AS.Klines_1  ) -> IO ()
anlytoBuy tbq conn msg tdepth ostvar klinetvar = 
   do
     res                                    <-    runRedis conn (getdiffintervalflow) 
     kline                                  <-    parsetokline msg
     let dcp                                =     read $ kclose kline :: Double
     bigintervall                           <-    analysismindo (fst res ) dcp 
     ((thresholdup,thresholddo),reasons)    <-    crossminstra bigintervall dcp
     atdepth                                <-    readTVarIO tdepth 
     atkline                                <-    readTVarIO klinetvar 
     apr                                    <-    AS.depthmidpr atdepth dcp
     let ares                               =     AS.getBidAskNum apr atdepth
     ((sndquan,sedtrend),(reason,rtype)  )  <-    secondrule apr ares
     ((volumnpred,vtrend),vreason)          <-    volumn_stra_1m atkline dcp 
     timecurtime                            <-    getZonedTime >>= return.formatTime defaultTimeLocale "%Y-%m-%d,%H:%M %Z"
     curtimestampi                          <-    getcurtimestamp
     let reachwavelimitpred                 =     ((/= "no")  $ fst reasons) && ((/= "no")  $ snd reasons)
     ((needlepred,ntrend),nreason)          <-    needlestra  bigintervall
     (dd,dd2)                               <-    getnextgriddiff bigintervall 0 dcp
     let aimquan = case rtype of 
                      "1" -> 0
                      "2" -> 1
                      _   -> 2
     let minquan = minbasequan + aimquan 

     when (sedtrend==AS.ND) $ do
         logact logByteStringStdout $ BC.pack $ show ("sndruleup is ---- !",thresholdup,thresholddo,sndquan,timecurtime,dcp)
     when (sedtrend==AS.UP) $ do
         let sumresb = (-thresholdup) +sndquan -- aim is up
         let sumresm = (-((fromIntegral thresholdup)/4)) +(fromIntegral sndquan) -- aim is up
         let sumresm2 = (-((fromIntegral thresholdup)/3.5)) +(fromIntegral sndquan) -- aim is up
         let sumresm3 = (-((fromIntegral thresholdup)/3)) +(fromIntegral sndquan) -- aim is up
         let sumresm4 = (-((fromIntegral thresholdup)/2)) +(fromIntegral sndquan) -- aim is up
         logact logByteStringStdout $ BC.pack $ show ("sndruleup is ---- !",thresholdup,thresholddo,sndquan,sumresb,timecurtime,dcp)
         case (sumresb>0) of 
            True  -> do
                       let aresquan        = toInteger basequan 
                       let stopclosegrid   = 0.0005
                       prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 
            False -> do 
                       when (volumnpred == True && vtrend ==AS.UP && vreason == "small" && reason /="no"  && sumresm >0 && sumresm3 <0 ) $ do 
                           let aresquan        = toInteger (minquan+30)
                           let stopclosegrid   = 0.00041
                           prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 

                       when (volumnpred == True && vtrend ==AS.UP && vreason == "small" && reason /="no"  && sumresm3 >0 && sumresm4 <0) $ do 
                           let aresquan        = toInteger (minquan+130)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 

                       when (volumnpred == True && vtrend ==AS.UP && vreason == "small" && reason /="no" && sumresm4 >0 ) $ do 
                           let aresquan        = toInteger (minquan+240)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 

                       when (volumnpred == True && vtrend ==AS.UP && vreason == "big" && reason /= "no" && sumresm >0  && sumresm2 < 0) $ do 
                           let aresquan        = toInteger (minquan+20)
                           let stopclosegrid   = 0.00041
                           prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 

                       when (volumnpred == True && vtrend ==AS.UP && vreason == "big" && reason /="no" && sumresm3 >0 && sumresm4 < 0)  $ do 
                           let aresquan        = toInteger (minquan+120)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 

                       when (volumnpred == True && vtrend ==AS.UP && vreason == "big" && reason /="no" && sumresm4 >0 ) $ do 
                           let aresquan        = toInteger (minquan+230)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 

                       when ((reason =="cc1" ) && sumresm >0   ) $ do -- && (reachwavelimitpred == True)) $ do 
                           let aresquan        = toInteger (minquan*4)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 

                       when ((reason =="cc2" ) && sumresm >0   ) $ do -- && (reachwavelimitpred == True)) $ do 
                           let aresquan        = toInteger (minquan*2)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 

                       when ((reason =="pr" )  && sumresm >0   ) $ do -- && (reachwavelimitpred == True)) $ do 
                           let aresquan        = toInteger (minquan*2+10)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 

                       when ((reason =="pr1" )  && sumresm3 >0  ) $ do -- && (reachwavelimitpred == True)) $ do 
                           let aresquan        = toInteger (minquan*6)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 

                       when ((reason =="pr1" )  && sumresm >0  ) $ do -- && (reachwavelimitpred == True)) $ do 
                           let aresquan        = toInteger (minquan*3)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 

                       when ((ntrend == AS.UP ) && (needlepred == True) && (nreason == "1h") &&  sumresm >0 ) $ do 
                           let aresquan        = toInteger (9*minquan)
                           let stopclosegrid   = 0.0005
                           prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 

                       when ((ntrend == AS.UP ) && (needlepred == True) && (nreason == "4h") &&  sumresm >0 ) $ do 
                           let aresquan        = toInteger (20*minquan)
                           let stopclosegrid   = 0.0018
                           prepopenfun stopclosegrid aresquan ostvar BUY dcp curtimestampi tbq 
                       

     when (sedtrend==AS.DO) $ do
         let sumresb = (thresholddo) + sndquan -- aim is down
         let sumresm = ((fromIntegral thresholddo)/4) + ( fromIntegral sndquan) -- aim is down
         let sumresm2 = ((fromIntegral thresholddo)/3.5) + ( fromIntegral sndquan) -- aim is down
         let sumresm3 = ((fromIntegral thresholddo)/3) + ( fromIntegral sndquan) -- aim is down
         let sumresm4 = ((fromIntegral thresholddo)/2) + ( fromIntegral sndquan) -- aim is down
         logact logByteStringStdout $ BC.pack $ show ("sndruledo is ---- !",thresholdup,thresholddo,sndquan,sumresb,timecurtime,dcp)
         case (sumresb<0) of
            True -> do
                       let aresquan        = toInteger basequan 
                       let stopclosegrid   = 0.0005
                       prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 
            False ->do
                       when (volumnpred == True && vtrend ==AS.DO && vreason == "small" && reason /= "no" && sumresm<0 && sumresm3>0) $ do 
                           let aresquan        = toInteger (minquan+30)
                           let stopclosegrid   = 0.00041
                           prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 

                       when (volumnpred == True && vtrend ==AS.DO && vreason == "small" && reason /="no" && sumresm3<0 && sumresm4>0) $ do 
                           let aresquan        = toInteger (minquan+130)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 

                       when (volumnpred == True && vtrend ==AS.DO && vreason == "small" && reason /="no" && sumresm4<0 ) $ do 
                           let aresquan        = toInteger (minquan+240)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 

                       when (volumnpred == True && vtrend ==AS.DO && vreason == "big" && reason /="no" && sumresm <0 && sumresm3 > 0 ) $ do 
                           let aresquan        = toInteger (minquan+20)
                           let stopclosegrid   = 0.00041
                           prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 

                       when (volumnpred == True && vtrend ==AS.DO && vreason == "big" && reason /="no"  && sumresm3 <0 && sumresm4 > 0) $ do 
                           let aresquan        = toInteger (minquan+120)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 

                       when (volumnpred == True && vtrend ==AS.DO && vreason == "big" && reason /="no"  && sumresm4 <0) $ do 
                           let aresquan        = toInteger (minquan+230)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 

                       when ((reason =="cc1" ) && sumresm <0) $ do -- && (reachwavelimitpred == True)) $ do 
                           let aresquan        = toInteger (minquan*4)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 

                       when ((reason =="cc2" ) && sumresm <0 ) $ do -- && (reachwavelimitpred == True)) $ do 
                           let aresquan        = toInteger (minquan*2)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 

                       when ((reason =="pr" ) && sumresm < 0) $ do -- && (reachwavelimitpred == True)) $ do 
                           let aresquan        = toInteger (minquan*2+10)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 

                       when ((reason =="pr1" ) && sumresm3 <0) $ do -- && (reachwavelimitpred == True)) $ do 
                           let aresquan        = toInteger (minquan*6)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 

                       when ((reason =="pr1" ) && sumresm <0) $ do -- && (reachwavelimitpred == True)) $ do 
                           let aresquan        = toInteger (minquan*3)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 

                       when ((ntrend == AS.DO ) && (needlepred == True) && (nreason == "1h") && sumresm <0  ) $ do 
                           let aresquan        = toInteger (9*minquan)
                           let stopclosegrid   = 0.0004
                           prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 

                       when ((ntrend == AS.DO ) && (needlepred == True) && (nreason == "4h") && sumresm <0 ) $ do 
                           let aresquan        = toInteger (20*minquan)
                           let stopclosegrid   = 0.0018
                           prepopenfun stopclosegrid aresquan ostvar SELL dcp curtimestampi tbq 

   `catch` (\(e :: SomeException) -> do
                SI.hPutStrLn stderr $ "Goterror1: " ++ show e)
  

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
    let dhhvo = hhvo s 
    let ddst = fromInteger dst :: Double
    let sst = BL.fromString $ show dst
    let sop = BL.fromString dop
    let scp = BL.fromString dcp
    let shp = BL.fromString dhp
    let slp = BL.fromString dlp
    let shhvo = BL.fromString dhhvo
    let abyvaluestr = BL.fromString  $ DL.intercalate "|" [show dst,dop,dcp,dhp,dlp,dhhvo]
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
