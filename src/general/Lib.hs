{-# LANGUAGE DeriveGeneric #-}
module Lib
    ( 
     getrsi,
     getnewgrid,
     getnewgriddiff,
     getnewgridlevel
    ) where
import GHC.Generics
import Data.Aeson
import Data.Text
import Data.List as DL
import Prelude as DT
import Httpstructure
import Control.Monad
import Control.Monad.IO.Class
import Analysistructure

getrsi :: [Hlnode] -> Int -> IO (Int,String)
getrsi hl hllen = do 
  let klen = hllen
  let updiff   =  [(cprice $ (!!i) hl) -(cprice $ (!!(i+1)) hl)   | i <- [0..klen-2], (cprice $ (!!i) hl) -(cprice $ (!!(i+1)) hl) > 0] 
  let downdiff =  [(cprice $ (!!i) hl) -(cprice $ (!!(i+1)) hl)   | i <- [0..klen-2], (cprice $ (!!i) hl) -(cprice $ (!!(i+1)) hl) < 0] 

  let gain = case (DL.length updiff) of 
                  x|x<1 -> 0.00001 
                  _     -> (abs $ sum updiff)
  let loss = case (DL.length downdiff) of 
                  x|x<1 -> 0.00001
                  _     -> (abs $ sum downdiff)
  --liftIO $ print (updiff,downdiff,gain,loss)
  let rs = gain/loss 
  --liftIO $ print (rs)
  let rsi  = (100 - (100 /(1+rs)))
  return (round rsi,"")

getboll :: [Hlnode] -> Int -> IO (Int,String)--
getboll hl hllen = pure (0,"")

getnewgrid :: Integer -> Double
getnewgrid quan = 
                  case quan of 
                      x|x==1000           -> 0.0006        -- map to 1000
                      x|x==2000           -> 0.001         -- map to 2000
                      x|x==4000           -> 0.004         -- map to 4000
                      x|x==8000           -> 0.08          -- map to 8000
                      x|x<=100            -> 0.0005
                      x|x<=200            -> 0.0005
                      x|x<=360            -> 0.0012
                      x|x<=500            -> 0.002
                      x|x<1000&&x>500     -> 0.002
                      x|x<=2000&&x>1000   -> 0.006
                      x|x<=4000&&x>2000   -> 0.01
                      x|x<=8000&&x>4000   -> 0.03
                      x|x<=16000&&x>8000  -> 0.09
                      _                   -> 0.09

getnewgriddiff :: Double -> Double
getnewgriddiff grid = 
                  case grid of 
                      x|x==0.0006            -> 40  * grid  -- map to 1000
                      x|x==0.001             -> 60  * grid  -- map to 2000
                      x|x==0.004             -> 60  * grid  -- map to 4000
                      x|x==0.08              -> 10  * grid  -- map to 8000
                      x|x<=0.0005            -> 16   * grid
                      x|x<=0.0012            -> 10  * grid
                      x|x<=0.002             -> 40  * grid
                      x|x<=0.006             -> 40  * grid
                      x|x<=0.01              -> 40  * grid
                      x|x<=0.03              -> 40  * grid
                      x|x<=0.2               -> grid
                      x|x<=0.5               -> grid
                      _                      -> grid

getnewgridlevel :: Integer -> Double
getnewgridlevel quan = 
                  case quan of 
                      x|x<=120            -> 5
                      x|x<=220            -> 10
                      x|x<=260            -> 15
                      x|x>=260&&x<500     -> 20
                      x|x<=1000&&x>500    -> 30
                      x|x<=2000&&x>1000   -> 40
                      x|x<=4000&&x>2000   -> 70
                      x|x<=8000&&x>4000   -> 120
                      x|x<=16000&&x>8000  -> 200
                      _                   -> 128 
