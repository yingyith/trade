{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Analysistructure
    ( 
      Klinenode (..),
      green_or_red_pred,
      same_color_pred,
      get_largest_volumn,
      get_smlgest_volumn,
      choose_proper_wave,
      volumn_pred,
      volumn_pred_vice,
      Klines_1 (..),
      Hlnode (..),
      Trend  (..),
      Ticker  (..),
      Depthset (..),
      biddepthsheet,
      askdepthsheet,
      depthmidpr,
      getBidAskNum,
      retposfromgrid
    ) where
import Control.Applicative
import qualified Text.URI as URI
import qualified Data.ByteString.Char8 as B
import Data.Maybe (fromJust)
import qualified Data.Map as DM
import qualified Data.HashMap  as DHM
import Control.Monad
import Control.Monad.IO.Class as I 
import qualified Data.Vector as V
import qualified Data.ByteString.Lazy.Internal as BLI
import qualified Data.ByteString.UTF8 as BL
import Data.Aeson as A
import Data.List as DL
import Data.Aeson.Types as AT
import Data.Text (Text)
import Data.Typeable
import Data.Ord
import GHC.Generics
import Network.HTTP.Req
import Database.Redis
import Data.String.Class as DC
import Globalvar
import Colog (LogAction,logByteStringStdout)
import Logger


data Depthset = Depthset {
      depu       :: Int,
      depU       :: Int,
      deppu      :: Int,
      intersset  :: DHM.Map BL.ByteString Double ,
      bidset     :: DHM.Map BL.ByteString Double ,------[(Double,BL.ByteString)],
      askset     :: DHM.Map BL.ByteString Double                      --[(Double,BL.ByteString)]
} deriving (Show,Generic) 

data Ticker = Ticker {
      prdiff_24h            :: Double,
      prdiff_ratio_24h      :: Double,
      prdiff_avg_24h        :: Double,
      pr_deal_latest        :: Double,
      volumn_deal_latest    :: Integer
                      
} deriving (Show,Generic) 

convbstodoublelist :: (BL.ByteString,Double) ->  (Double,Double)
convbstodoublelist ml = (read $  BL.toString $ fst ml :: Double,snd ml)


depthmidpr :: Depthset -> Double ->IO  ((Double,Double),Double)
depthmidpr adepth dcp  = do 
    let a   = bidset adepth 
    let b   = askset adepth
    let ins = intersset  adepth
    let alist = map convbstodoublelist $  DHM.toList $ ins 
    let minprt = foldr (\(xf,xs) (yf,ys) -> if ((xf < yf) && ((abs (xf-dcp))<0.0005))   then (xf,xs) else (yf,ys) )  (11,11) alist 
    let maxprt = foldr (\(xf,xs) (yf,ys) -> if ((xf > yf) && ((abs (xf-dcp))<0.0005))   then (xf,xs) else (yf,ys) )  (0   ,0   ) alist
    liftIO $ logact logByteStringStdout $ B.pack  (show ("get startpr is -----",alist,minprt,maxprt))
    return ((fst minprt,fst maxprt),dcp)


getbiddiffquanpred ::Double -> Double -> BL.ByteString -> Double -> Bool 
getbiddiffquanpred  checkpr diff  key value  =   
    case (read $ BL.toString $ key ::Double) of 
        x|(x >= (checkpr - diff)) && (x <= checkpr) ->  True
        _                                           ->  False

getaskdiffquanpred ::Double -> Double -> BL.ByteString -> Double -> Bool 
getaskdiffquanpred  checkpr diff  key value  =   
    case (read $ BL.toString $ key ::Double) of 
        x|(x <= (checkpr + diff)) && (x >= checkpr) ->  True
        _                                           ->  False
    
choose_proper_wave :: Double -> Double -> Double -> Double
choose_proper_wave  ccc  ddd  eee = 
    case ((abs eee  )>0.09,(abs ddd)>0.13,(abs ccc)>0.19) of 
       (True , True  ,True  )  -> eee 
       (True , True  ,False )  -> eee 
       (True , False ,False )  -> eee 
       (True , False ,True  )  -> eee 
       (False, False ,True  )  -> ccc 
       (False, False ,False )  -> ddd 
       (False, True  ,True  )  -> ddd 
       (False, True  ,False )  -> ddd 

getBidAskNum :: ((Double,Double),Double) -> Depthset -> [(Double,Double)]  --diff have 0.0005,0.001,0.002,for up trend use all max data,for low trend ,use all min data
getBidAskNum apr dpdata = [
                           (
                           sum $ DHM.elems $  DHM.filterWithKey  (getbiddiffquanpred  ((snd apr)) 0.0002 )        $ bidset  dpdata, 
                           sum $ DHM.elems $  DHM.filterWithKey  (getbiddiffquanpred  ((snd apr)-0.0002) 0.0002 ) $ bidset  dpdata 
                           ),
                           (
                           sum $ DHM.elems $  DHM.filterWithKey  (getaskdiffquanpred  ((snd apr)) 0.0002 )        $ askset  dpdata, 
                           sum $ DHM.elems $  DHM.filterWithKey  (getaskdiffquanpred  ((snd apr)+0.0002) 0.0002 ) $ askset  dpdata 
                           ),
                           (
                           sum $ DHM.elems $  DHM.filterWithKey  (getbiddiffquanpred  ((snd apr)-0.0002) 0.0002 ) $ bidset  dpdata,
                           sum $ DHM.elems $  DHM.filterWithKey  (getbiddiffquanpred  ((snd apr)-0.0004) 0.0002 ) $ bidset  dpdata 
                           ),
                           (
                           sum $ DHM.elems $  DHM.filterWithKey  (getaskdiffquanpred  ((snd apr)+0.0002) 0.0002 ) $ askset  dpdata,
                           sum $ DHM.elems $  DHM.filterWithKey  (getaskdiffquanpred  ((snd apr)+0.0004) 0.0002 ) $ askset  dpdata 
                           ),
                           ( 0,
                             0
                           ),
                           (
                           sum $ DHM.elems $  DHM.filterWithKey  (getbiddiffquanpred (snd apr) 0.0001 ) $ bidset  dpdata ,
                           sum $ DHM.elems $  DHM.filterWithKey  (getaskdiffquanpred  (snd apr) 0.0001 ) $ askset  dpdata 
                           ),
                           (
                           sum $ DHM.elems $  DHM.filterWithKey  (getbiddiffquanpred (snd apr) 0.0002 ) $ bidset  dpdata ,
                           sum $ DHM.elems $  DHM.filterWithKey  (getaskdiffquanpred  (snd apr) 0.0002 ) $ askset  dpdata 
                           ),
                           (sum $ DHM.elems $  DHM.filterWithKey  (getbiddiffquanpred (snd apr) 0.0005 ) $ bidset  dpdata ,
                           sum $ DHM.elems $  DHM.filterWithKey  (getaskdiffquanpred  (snd apr) 0.0005 ) $ askset  dpdata 
                           ),
                           (sum $ DHM.elems $  DHM.filterWithKey  (getbiddiffquanpred (snd apr) 0.004 ) $ bidset  dpdata ,
                           sum $ DHM.elems $  DHM.filterWithKey  (getaskdiffquanpred  (snd apr) 0.004 ) $ askset  dpdata 
                           ),
                           (sum $ DHM.elems $  DHM.filterWithKey  (getbiddiffquanpred (snd apr) 0.008 ) $ bidset  dpdata ,
                           sum $ DHM.elems $  DHM.filterWithKey  (getaskdiffquanpred  (snd apr) 0.008 ) $ askset  dpdata 
                           ),
                           (sum $ DHM.elems $  DHM.filterWithKey  (getbiddiffquanpred (snd apr) 0.016 ) $ bidset  dpdata ,
                           sum $ DHM.elems $  DHM.filterWithKey  (getaskdiffquanpred  (snd apr) 0.016 ) $ askset  dpdata 
                           ),
                           (0 ,
                            0 
                           )]

getcurpraccu ::  Depthset -> Int     
getcurpraccu ordepth = 1 
     


getdepthweight :: Double -> Double -> Int
getdepthweight bcount acount = do 
    case (bcount-acount)/(max bcount acount) of 
        x|x<(diffspreadsheet!!1) && x>(diffspreadsheet!!0)  -> (depthrisksheet !! 0)
        x|x<(diffspreadsheet!!2) && x>(diffspreadsheet!!1)  -> (depthrisksheet !! 1)
        x|x<(diffspreadsheet!!3) && x>(diffspreadsheet!!2)  -> (depthrisksheet !! 2)
        x|x<(diffspreadsheet!!4) && x>(diffspreadsheet!!3)  -> (depthrisksheet !! 3)
        x|x<(diffspreadsheet!!5) && x>(diffspreadsheet!!4)  -> (depthrisksheet !! 4)
        x|x<(diffspreadsheet!!6) && x>(diffspreadsheet!!5)  -> (depthrisksheet !! 5)
        x|x<(diffspreadsheet!!7) && x>(diffspreadsheet!!6)  -> (depthrisksheet !! 6)
        _                                                   -> (depthrisksheet !! 0)


data Trend = UP | DO | ND deriving (Enum,Eq,Show) --"up","down","not determine"
                 

data Hlnode = Hlnode {
              time   :: Integer ,       
              hprice :: Double  ,
              lprice :: Double  ,
              rank   :: Integer ,
              stype  :: String  , -- high or low` 
              rtype  :: String  ,  -- '5min' or '1h'
              cprice :: Double  ,
              hvo :: Double  
} deriving (Show,Generic)

data Klinenode = Klinenode {
              knoprice  :: Double  ,
              kncprice  :: Double  ,
              knhprice  :: Double  ,
              knlprice  :: Double  ,
              knvolumn  :: Integer ,
              knamount  :: Double  ,
              knpvolumn :: Integer ,
              knpamount :: Double  ,
              knendsign  :: Bool    
} deriving (Show,Generic)


data Klines_1 = Klines_1 {
             klines_1m :: [Klinenode],
             klines_1s :: [Klinenode]
} deriving (Show,Generic) 

green_or_red_pred  :: Klinenode -> Bool 
green_or_red_pred  knode =  ((knoprice knode) <= (knlprice knode))
              
volumn_pred  :: Klinenode -> Double -> Double -> Bool 
volumn_pred  knode vomax vomin =  (( fromIntegral $ knvolumn knode :: Double) >= vomax )
                                || (( fromIntegral $ knvolumn knode :: Double) <= vomin )

volumn_pred_vice  :: Klinenode  -> Double -> Bool 
volumn_pred_vice  knode voavg  =  (( fromIntegral $ knvolumn knode :: Double) >= (2.5*voavg) )

get_largest_volumn :: [Klinenode] -> (Klinenode,Int)
get_largest_volumn klines = maximumBy (comparing  (knvolumn.fst))  (zip klines [0..]) 

get_smlgest_volumn :: [Klinenode] -> (Klinenode,Int)
get_smlgest_volumn klines = minimumBy (comparing  (knvolumn.fst))  (zip klines [0..]) 

same_color_pred ::  [Klinenode] -> Bool
same_color_pred klines  = 
            foldr (\x y -> if ((((green_or_red_pred x)==(green_or_red_pred $ (!!0) klines)) ||  y)) then True else False     )  True  klines   

biddepthsheet :: DM.Map String Int 
biddepthsheet  = DM.fromList []

askdepthsheet :: DM.Map String Int 
askdepthsheet  = DM.fromList []

retposfromgrid :: [Double]-> Double -> [[Double]] -> IO (Integer,[Double])
retposfromgrid dll curprice dlsheet = do 
            --get current position from redis
            --if grid exists which mean have quantity,then compare the open gridsheet with now gridsheet ,check if or not have change to profit,or admit loss ,close order
--            liftIO $ print (dlsheet)
            let posindex = 0
            let base = 10
            let dl = [0]++dll
            let indexitem = [i| i<-[1..((DL.length dl)-1)],(dl!!(i-1))<curprice && (dl!!i)>=curprice]
            let lowp = dl!!(indexitem!!0)
            let highp = dl!!((indexitem!!0)+1)
            let diff = (highp-lowp)/3
            let lefcond = (curprice >= (lowp+diff))
            let rigcond = (curprice <= (highp-diff))
            let res = case (lefcond,rigcond) of 
                          (True,True) ->   (base * ( 2 ^ posindex) :: Integer)
                          (_,_) ->  0
            return (res,dll)

