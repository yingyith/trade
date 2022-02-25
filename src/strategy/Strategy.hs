{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
module Strategy
    ( 
     secondrule,
     saferegionrule
    ) where
import Data.Monoid ((<>))
import Control.Monad
import Control.Exception
import Control.Monad.Trans (liftIO)
import Control.Concurrent
import Network.WebSockets (ClientApp, receiveData, sendClose, sendTextData)
import Network.WebSockets.Connection as NC
import Control.Concurrent.Async
--import Data.Text as T
import Data.Map as DM
import Data.Maybe
import Prelude as DT
import Data.Text.IO as TIO
import Data.ByteString (ByteString)
import Data.Text.Encoding
import System.IO as SI
import Data.Aeson
import Data.Aeson.Lens
import qualified Data.ByteString.Char8 as B
import Data.Aeson.Types
import Analysistructure as AS
import Httpstructure
import Globalvar


--every grid have a position value, 1min value -> 15  up_fast->5      oppsite -> -15 fall_fast -> -25
--                                  5min value -> 20  up_fast->5     oppsite -> -10 fall_fast -> -20
--                                  15min value -> 15 up_fast->5      oppsite -> -10 fall_fast -> -20
--                                  1hour value -> 10 up_fast->5      oppsite -> -15 fall_fast -> -10
--                                  4hour value -> 30 up_fast->-10     oppsite -> -40 fall_fast -> -60
--                                  1day value -> 5   up_fast->-5      oppsite -> -5  fall_fast -> 0
--                                  3day value -> 5   up_fast->-5      oppsite -> -5  fall_fast -> 0
--                                  only sum of all predication > = 0 ,then can open
risksheet :: DM.Map String [Integer]
risksheet = fromList [
             ("3m", [-150,-150,-15,-45]),
             ("5m", [10,-15,10,-25]),
             ("15m",[-150,-125,10,-15]),   --15min highpoint  , up_fast must be minus -25 or smaller
             ("1h", [20,20,-10,-25]),    -- long interval have effect on short interval ,if 1hour is rise ,then ,15min low point  should rely on ,easy to have benefit.
             ("4h", [25,20,-15,-25]),
             ("12h", [5,5,0,0]),
             ("3d", [0,5,0,0])
            ]


saferegionrule :: (String,Double) -> [Double] -> IO Integer
saferegionrule minpr sheet  = do 
   let lp = sheet!!0
   let hp = sheet!!1
   let lhdiff = hp-lp
   let interval = fst minpr
   let pr = snd minpr
   let action | (pr >= (hp-lhdiff/4)) = (return $ (fromJust $ risksheet!?interval)!!1)
              | (pr < (hp-lhdiff/4) && pr >= (hp-lhdiff/3)) = (return $ (fromJust $  risksheet!?interval)!!0)
              | (pr > (lp+lhdiff/4) && pr <= (lp+lhdiff/3)) = (return $ (fromJust $ risksheet!?interval)!!2)
              | (pr <= (lp+lhdiff/4))  = (return $ (fromJust $  risksheet!?interval)!!3)
              | (pr > (lp+lhdiff/3) && pr < (hp-lhdiff/3)) = return 15
   action

gethlsheetsec :: Int -> [ Klinedata ] -> IO (AS.Hlnode)
gethlsheetsec index kll =  do 
    --- rule1: if last one stick < last low point , return  -unlimitKlinedata
  --    rule2: if near high point then not open,if near low point can open  ,
    let curitem  = kll !! index 
    let nextitem  = kll !! (index + 1) 
    let curitemt = ktime curitem
    let curitemcp = read $ kclose curitem  :: Double
    let nextitemcp = read $ kclose nextitem :: Double 
    let predication = (curitemcp - nextitemcp) 
    let res = case compare predication  0 of 
                  LT   ->  (AS.Hlnode curitemt 0 curitemcp 0 "low" "1s")
                  GT ->  (AS.Hlnode curitemt curitemcp 0 0 "high" "1s")
                  EQ ->  (AS.Hlnode curitemt curitemcp 0 0 "wsmall" "1s")
    return res


secondrule :: [Klinedata] -> IO Integer
secondrule records = do 
                        let slenrecord = length records
                        liftIO $ print (slenrecord)
                        case compare slenrecord (fromIntegral secondstick)  of 
                             GT -> do  
                                        rehllist <- mapM ((\s ->  gethlsheetsec s records) :: Int -> IO AS.Hlnode ) [0..80] :: IO [AS.Hlnode]
                                        let reslist = [(xlist!!x,x)|x<-[1..(length xlist)-2],((stype $ xlist!!(x-1)) /= (stype $ xlist!!x)) && ((stype $ xlist!!x) /= "wsmall")] where xlist = rehllist
                    --lookup the highlow point near from time,if it only apprear on one stick ,then the safe place should lower
                    --lookup the nearest point from distance in price diff. 
                                        let currentpr = max (hprice $ fst $ reslist !! 0) (lprice $ fst $ reslist !! 0)
                                        let highsheet = [((hprice $ xlist!!x),x)| x<-[1..(length xlist)-2],((hprice $ xlist!!x) > 0.1)  && ((stype $ xlist!!x) == "high")] where xlist = rehllist
                                        let lowsheet = [((lprice $ xlist!!x),x)| x<-[1..(length xlist)-2] ,((lprice $ xlist!!x) > 0.1)  && ((stype $ xlist!!x) == "low")] where xlist = rehllist
                                        let highgrid = DT.foldr (\(l,h) y -> (max l (fst y),h)) (highsheet!!0) highsheet
                                        let lowgrid = DT.foldr (\(l,h) y -> (min l (fst y),h)) (lowsheet!!0)  lowsheet 
                                        let highpr = fst highgrid 
                                        let lowpr = fst lowgrid 
                                        let diff = highpr - lowpr
                                        liftIO $ print (highpr,lowpr)
                                        liftIO $ print ("second high low price is--------------------------------")
                                       -- return 0 
                                        if (abs (highpr - lowpr ) <=0.005)
                                           then do return (-100000)
                                           else do 
                                                   if ( (snd highgrid) < (snd lowgrid) && currentpr > lowpr ) --low point is near ,check diff 
                                                      then do 
                                                          if (currentpr > (highpr-diff/2)) 
                                                             then do return 25 
                                                             else do return (-100000)                                   -- currrentpr > high-1/3 diff  ,no open
                                                                                                                -- if hight point only single stick,have big  diff to other ,then diff should be bigger
                                                                                                         -- currrentpr < high-1/3 diff  , open 25
                                                                     
                                                               
                                                      else do
                                                          return (-100000)
                             LT -> return (-1000000)  
                             EQ -> return (-1000000)
                             _  -> return (-1000000)
         -- if nearest point is high and > high-1/3 grid ,do not open 
         --                          if  <high-1/3 and > low+1/3 , open small 
         --                          if  <low+/1/3 and > low+1+1/4 , open small 
         --                          if  <low+/1/3 and > low+1+1/4 , no open
  --   if close to 3m or 5m low point ,then do not open ,but after pass ,then open few 
  --   if close to 15m low point  ,then do not open,but after back ,open .close pr due to  hold position and price after  merge
  --   if close to 1h low point ,then do not open,but after back ,open .close pr due to  hold position and price after  merge
        -- liftIO $ print (highsheet,lowsheet)
   -- liftIO $ print (reslist)
    -- case (compare  (length records) 45)  of 
    --      GT -> return 0
    --      LT -> return 0
    --      EQ -> return 0
    

closerule :: IO ()
closerule = do
    -- rule1: if base on second interval, the benefit diff should be low like 0.0002
    return ()
   
