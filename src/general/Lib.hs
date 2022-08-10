{-# LANGUAGE DeriveGeneric #-}
module Lib
    ( 
     getrsi,
     getnewgrid,
     getnewgriddiff,
     getnextgriddiff,
     getnewgridlevel
    ) where
import GHC.Generics
import Data.Aeson
import Data.Text
import Data.List as DL
import Prelude as DT
import Data.ByteString.Char8 as  BC
import Logger
import Colog (LogAction,logByteStringStdout)
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
                      x|x==2200           -> 0.0021         -- map to 2000
                      x|x==4000           -> 0.004         -- map to 4000
                      x|x==8000           -> 0.08          -- map to 8000
                      x|x<=110            -> 0.0004
                      x|x<=120            -> 0.0004
                      x|x<=200            -> 0.0012
                      x|x<=400            -> 0.0012
                      x|x<=500            -> 0.002
                      x|x<1000&&x>500     -> 0.001
                      x|x<=2000&&x>1000   -> 0.004
                      x|x<=4000&&x>2000   -> 0.0055
                      x|x<=8000&&x>4000   -> 0.03
                      x|x<=16000&&x>8000  -> 0.09
                      _                   -> 0.09

getnextgriddiff :: [(((Int,(Double,Double)),(String,Int)),[Hlnode])] -> Integer -> Double -> IO (Double,Integer)  -- return next appand diff distance and appand quant times
getnextgriddiff abcc quan bpr = do 
                             let abc                       =        [( snd $ fst $ fst i)|i<-abcc] 
                             let hldifflist                =        [((fst i)-(snd i))|i<-abc] 
                             let hllist                    =        DT.concatMap (\(a,b)-> [a,b]) abc 
                             let uppr                      =        [i|i<- hllist,i>bpr]
                             let dopr                      =        [i|i<- hllist,i<bpr]
                             let udiff                     =        DT.map (\x -> (x- bpr)) uppr
                             let ddiff                     =        DT.map (\x -> (bpr-x)) dopr
                             liftIO $ logact logByteStringStdout $ BC.pack $ show (" rsik is ---- !",hllist,uppr,dopr,udiff,ddiff)
                             --group the array to clear groups which have obvious diff large than 0.002
                             return (0,0)

getnewgriddiff :: Double -> Double
getnewgriddiff grid = 
                  case grid of 
                      x|x==0.0002            -> 40  * grid  
                      x|x==0.0007            -> 40  * grid  
                      x|x==0.0006            -> 12  * grid  
                      x|x==0.001             -> 20  * grid  
                      x|x==0.004             -> 20  * grid  
                      x|x==0.08              -> 10  * grid  
                      x|x<=0.0004            -> 10   * grid
                      x|x<=0.0005            -> 1000  * grid
                      x|x<=0.0012            -> 20  * grid
                      x|x<=0.002             -> 45  * grid
                      x|x<=0.0021            -> 100  * grid
                      x|x<=0.0022            -> 30  * grid
                      x|x<=0.004             -> 12  * grid
                      x|x<=0.0055            -> 18  * grid
                      x|x<=0.01              -> 40  * grid
                      x|x<=0.03              -> 40  * grid
                      x|x<=0.09              -> 10  * grid
                      x|x<=0.2               -> grid
                      x|x<=0.5               -> grid
                      _                      -> grid

splitappendgrid :: [Double] -> [Double] -> (Double,Integer)   -- return next appand quan and diff
splitappendgrid gridlu  gridld = (0,0) 

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
