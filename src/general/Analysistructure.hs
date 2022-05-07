{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Analysistructure
    ( 
      Hlnode (..),
      Depthset (..),
      biddepthsheet,
      askdepthsheet,
      depthmidpr,
      getBidAskNum,
      retposfromgrid
    ) where
import Control.Applicative
import qualified Text.URI as URI
import qualified Data.ByteString  as B
import Data.Maybe (fromJust)
import qualified Data.Map as DM
import qualified Data.HashMap  as DHM
import Control.Monad
import Control.Monad.IO.Class as I 
import qualified Data.Vector as V
import qualified Data.ByteString.Lazy.Internal as BLI
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.UTF8 as BL
import Data.Aeson as A
import Data.List as DL
import Data.Aeson.Types as AT
import Data.Text (Text)
import Data.Typeable
import GHC.Generics
import Network.HTTP.Req
import Database.Redis
import Data.String.Class as DC
import Globalvar


data Depthset = Depthset {
      depu       :: Int,
      depU       :: Int,
      deppu      :: Int,
      intersset  :: DHM.Map BL.ByteString Double ,
      bidset     :: DHM.Map BL.ByteString Double ,------[(Double,BL.ByteString)],
      askset     :: DHM.Map BL.ByteString Double                      --[(Double,BL.ByteString)]
} deriving (Show,Generic) 

convbstodoublelist :: (BL.ByteString,Double) ->  (Double,Double)
convbstodoublelist ml = (read $  BL.toString $ fst ml :: Double,snd ml)


depthmidpr :: Depthset  ->IO  (Double,Double)
depthmidpr adepth  = do 
    let a = bidset adepth 
    let b = askset adepth
    let alist = map convbstodoublelist $  DHM.toList $ DHM.intersection a  b
    let minprt = foldr (\(xf,xs) (yf,ys) -> if xf < yf then (xf,xs) else (yf,ys) )  (1111,1111) alist 
    let maxprt = foldr (\(xf,xs) (yf,ys) -> if xf > yf then (xf,xs) else (yf,ys) )  (0   ,0   ) alist
    return (fst minprt,fst maxprt)

getbiddiffquanpred ::Double -> Double -> BL.ByteString -> Double -> Bool 
getbiddiffquanpred  checkpr diff  key value  =   
    case (read $ BL.toString $ key ::Double) of 
        x|(x <= (checkpr + diff)) && (x >= checkpr) ->  True
        _                                           ->  False

getaskdiffquanpred ::Double -> Double -> BL.ByteString -> Double -> Bool 
getaskdiffquanpred  checkpr diff  key value  =   
    case (read $ BL.toString $ key ::Double) of 
        x|(x >= (checkpr - diff)) && (x <= checkpr) ->  True
        _                                           ->  False
    

getBidAskNum :: (Double,Double) -> Depthset -> (Double,Double)  --diff have 0.0005,0.001,0.002
getBidAskNum apr dpdata = (sum $ DHM.elems $  DHM.filterWithKey  (getbiddiffquanpred (fst apr) 0.0005 ) $ bidset  dpdata ,
                           sum $ DHM.elems $  DHM.filterWithKey  (getaskdiffquanpred (snd apr) 0.0005 ) $ askset  dpdata)

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
        x|x<(diffspreadsheet!!8) && x>(diffspreadsheet!!7)  -> (depthrisksheet !! 7)
        _                                                   -> (depthrisksheet !! 0)

diffspreadsheet :: [Double]
diffspreadsheet = [-0.1 ,0.1  ,0.2  ,0.4  ,0.8  ,1.2  ,1.6  ,2] 

depthrisksheet :: [Int] 
depthrisksheet = [-2000  ,100  ,200  ,300  ,400  ,600  ,800  , 1000  ]   -- 
                 

data Hlnode = Hlnode {
              time   :: Integer ,       
              hprice :: Double  ,
              lprice :: Double  ,
              rank   :: Integer ,
              stype  :: String  , -- high or low` 
              rtype  :: String  ,  -- '5min' or '1h'
              cprice :: Double
              } deriving (Show,Generic)


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

