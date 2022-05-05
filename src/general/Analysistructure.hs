{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Analysistructure
    ( 
      Hlnode (..),
      Depthset (..),
      biddepthsheet,
      askdepthsheet,
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


depthmidpr :: DHM.Map BL.ByteString Double ->  DHM.Map BL.ByteString Double -> DHM.Map BL.ByteString Double
depthmidpr a  b  = DHM.intersection a  b

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

