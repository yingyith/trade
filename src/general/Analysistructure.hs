{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Analysistructure
    ( 
      Hlnode (..),
      retposfromgrid
    ) where
import Control.Applicative
import qualified Text.URI as URI
import qualified Data.ByteString  as B
import Data.Maybe (fromJust)
import qualified Data.Map as Map
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

--data HLtree  = Leaf {
--               index :: Integer,
--               price :: Double,
--               rank :: Integer,
--               stype :: String }
--               | Branch HLtree HLtree deriving Show 

data Hlnode = Hlnode {
              time :: Integer,       
              hprice :: Double,
              lprice :: Double,
              rank :: Integer,
              stype :: String, -- high or low` 
              rtype :: String,  -- '5min' or '1h'
              cprice :: Double
              } deriving (Show,Generic)

--mix 1m and 5m kline analysis
--mix 5m and 15m kline analysis
--mix 5m and 15m kline analysis
  --plan a :   predicationA : 1m kline  $$ 5m kline ==> result
  --           predicationB : 1m kline $$ 3h kline  $$ 5m kline ==> result
  --           apply predicationA ruleB   
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

