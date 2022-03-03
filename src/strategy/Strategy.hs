{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
module Strategy
    ( 
     secondrule,
     minrule,
     genehighlowsheet,
     minrisksheet
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
import qualified Data.ByteString.UTF8 as BL
import Data.List.Split as DLT
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
--risksheet :: DM.Map String [Integer]
--risksheet = fromList [
--             ("3m", [-150,-150,-15,-45]),
--             ("5m", [10,-150,10,-25]),
--             ("15m",[-150,-150,10,-15]),   --15min highpoint  , up_fast must be minus -25 or smaller
--             ("1h", [20,20,-10,-25]),    -- long interval have effect on short interval ,if 1hour is rise ,then ,15min low point  should rely on ,easy to have benefit.
--             ("4h", [25,20,-15,-25]),
--             ("12h", [5,5,0,0]),
--             ("3d", [0,5,0,0])
--            ]

minrisksheet :: DM.Map String [Int] 
minrisksheet = fromList [
                 ("3m", [-10,45,-45,-105]), --first is up fast ,second is normal up,third is normal down ,forth is  fast down
                 ("5m", [-10,25,0,-15]), --
                 ("15m",[-75,30,-65,-25]),
                 ("1h", [5,15,-35,-25]),
                 ("4h", [5,15,-45,-25]),
                 ("12h",[5,15,-15,-25]),
                 ("3d", [5,15,0,-25])
            ]


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
    return res

minrule :: [AS.Hlnode]-> Double-> String -> IO Int
minrule ahl pr interval = do 
   -- get max (high)
   -- get min (low)
   -- confirm nearest (high or low)
   -- return this grid risk
   -- confirm if last stick is low or high point ,their  last how many sticks,if low,then good to buy ,but need to know how man position,and close price
   let reslist = [(xlist!!x,x)|x<-[1..(length xlist)-2],((stype $ xlist!!(x-1)) /= (stype $ xlist!!x)) && ((stype $ xlist!!x) /= "wsmall")] where xlist = ahl
   let highsheet = [((hprice $ xlist!!x),x)| x<-[1..(length xlist)-2],((hprice $ xlist!!x) > 0.1)  && ((stype $ xlist!!x) == "high")||((stype $ xlist!!x) == "wbig")] where xlist = ahl
   let lowsheet = [((lprice $ xlist!!x),x)| x<-[1..(length xlist)-2] ,((lprice $ xlist!!x) > 0.1)  && ((stype $ xlist!!x) == "low")||((stype $ xlist!!x) == "wbig")] where xlist = ahl
   let maxhigh = DT.foldr (\(l,h) y -> (max l (fst y),h)) (highsheet!!0) highsheet
   let minlow = DT.foldr (\(l,h) y -> (min l (fst y),h)) (lowsheet!!0)  lowsheet 
   let nearhigh = highsheet !!0
   let nearlow = lowsheet !!0
   let bigpredi =  (snd maxhigh) > (snd minlow) --true is low near
   let smallpredi =  (snd nearhigh)- (snd nearlow) 
                                                       -- if in 3mins ,any two sticks (max (bef,aft) - min (bef,aft) > 0.11,and check snds sticks,then prepare to buy)
  -- curpr( > high pr,return longer interval append position and 0) -  or (< low pr ,return -100000 ) 
  -- if (> low pr or < high pr,first to know near high or near low ,nearest point is (high-> mean to down ,quant should minus ) or (low-> mean to up  and return append position ) ,get up or low trend , then see small interval)
   case (pr > fst maxhigh,pr < fst  minlow ,bigpredi,smallpredi) of 
        (True,False,_,_) -> return ( (!!0) $ fromJust $  minrisksheet!?interval) -- up fast
        (False,True,_,_) -> return ( (!!3) $ fromJust $  minrisksheet!?interval) -- down fast
        (False,False,True,_) ->  return ( (!!1) $ fromJust $  minrisksheet!?interval) -- normal ()
        (False,False,False,_) ->  return ( (!!2) $ fromJust $  minrisksheet!?interval) -- normal ()
   


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


secondrule :: [Klinedata] -> IO Int
secondrule records = do 
                        let slenrecord = length records
                        liftIO $ print (slenrecord)
                        case compare slenrecord (fromIntegral secondstick)  of 
                             GT -> do  
                                        rehllist <- mapM ((\s ->  gethlsheetsec s records) :: Int -> IO AS.Hlnode ) [0..115] :: IO [AS.Hlnode]
                                        let reslist = [(xlist!!x,x)|x<-[1..(length xlist)-2],((stype $ xlist!!(x-1)) /= (stype $ xlist!!x)) && ((stype $ xlist!!x) /= "wsmall")] where xlist = rehllist
                                        let currentpr = max (hprice $ fst $ reslist !! 0) (lprice $ fst $ reslist !! 0)
                                        let highsheet = [((hprice $ xlist!!x),x)| x<-[1..(length xlist)-2],((hprice $ xlist!!x) > 0.1)  && ((stype $ xlist!!x) == "high")] where xlist = rehllist
                                        let lowsheet = [((lprice $ xlist!!x),x)| x<-[1..(length xlist)-2] ,((lprice $ xlist!!x) > 0.1)  && ((stype $ xlist!!x) == "low")] where xlist = rehllist
                                        let highgrid = DT.foldr (\(l,h) y -> (max l (fst y),h)) (highsheet!!0) highsheet
                                        let lowgrid = DT.foldr (\(l,h) y -> (min l (fst y),h)) (lowsheet!!0)  lowsheet 
                                        let highpr = fst highgrid 
                                        let lowpr = fst lowgrid 
                                        let diff = highpr - lowpr
                                        let wavediffpredi = (abs (highpr - lowpr ) <=0.005)
                                        let hlpredi = (snd highgrid) > (snd lowgrid)
                                        let prlocpredi = (currentpr < (highpr-diff*0.4)) && (currentpr >= (lowpr+diff/6))
                                        let lastjumppredi = (stype (rehllist!!0)=="low") && (stype (rehllist!!1)=="high") && (abs ((lprice $ rehllist!!0) -( hprice $ rehllist!!1))) > 0.01 
                                        case (wavediffpredi,hlpredi,prlocpredi,lastjumppredi) of 
                                            (True,_,_,_)-> return (-10000) 
                                            (False,True,True,False)-> return 70 
                                            (False,_,_,True)-> return 150
                                            (False,_,_,_)-> return (-10000)
                             LT -> return (-1000000)  
                             EQ -> return (-1000000)
