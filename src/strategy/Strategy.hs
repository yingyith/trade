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
import Data.List as DL
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
                 ("3m", [50,  60,  -45, -90 ]), --first is up fast ,second is normal up,third is normal down ,forth is  fast down
                 ("5m", [30,  60,  -60, -125 ]), --
                 ("15m",[60,  60,  -65, -125]),
                 ("1h", [30,  60,  -45, -175]),
                 ("4h", [5,   15,  -55, -50 ]),
                 ("12h",[5,   15,  -15, -25 ]),
                 ("3d", [5,   15,    0, -25 ])
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
   --liftIO $ print ("enter min do ---------------------")
   let highsheet = [((hprice $ fst x),snd x)| x<-xlist,((hprice $ fst x) > 0.1)  && ((stype $ fst x) == "high")||((stype $ fst x) == "wbig")] where xlist = reslist
   let lowsheet = [((lprice $ fst x),snd x)| x<-xlist ,((lprice $ fst x) > 0.1)  && ((stype $ fst x) == "low")||((stype $ fst x) == "wbig")] where xlist = reslist
   
   let nearhigh = case highsheet of 
                       [] -> last lowsheet 
                       _  -> highsheet!!0
   let nearlow = case lowsheet of 
                       [] -> last highsheet
                       _  -> lowsheet!!0
   let maxhigh = case highsheet of 
                       [] -> last lowsheet
                       _  -> DT.foldr (\(l,h) y -> if (l == (max l (fst y))) then (l,h) else y )  (highsheet!!0) highsheet
   let minlow  = case lowsheet of 
                       [] -> last highsheet 
                       _  -> DT.foldr (\(l,h) y -> if (l == (min l (fst y))) then (l,h) else y )  (lowsheet!!0)  lowsheet 
   let nearsndlow = DL.filter (\n-> ((snd n)< snd maxhigh)&& (snd n /= snd minlow) && (fst n < (fst maxhigh - (fst maxhigh - fst minlow)*0.66))) lowsheet
   let nearsndhigh = DL.filter (\n-> ((snd n)< snd minlow)&& (snd n /= snd maxhigh) && (fst n < (fst maxhigh - (fst maxhigh - fst minlow)*0.66))) highsheet
   let havesndlowpredi  = case nearsndlow of 
                           [] -> False
                           _ -> True
   let havesndhighpredi = case nearsndhigh of 
                           [] -> False
                           _ -> True

   let bigpredi =  (snd maxhigh) > (snd minlow) --true is low near
   let fastup = pr >= fst maxhigh
   let fastdown = pr <= fst minlow
   let waveveryfreq = case (havesndlowpredi,havesndhighpredi) of 
                           (True,True)-> True 
                           (_,_)      -> False
   let smallpredi = snd nearlow < snd nearhigh  -- true is low near
   let nowstick = ahl!!0
   let befstick = ahl!!1
   let minlasttwo = min (lprice nowstick) (lprice befstick)
   let lasttwodiff =abs (lprice nowstick - lprice befstick)
   let lastonediff =abs (lprice befstick - lprice nowstick)
   let threeminrulepredi = ((stype nowstick == "low")&&(stype befstick == "low") && (pr < minlasttwo+ 1/3*lasttwodiff)&& (lasttwodiff > 0.012) && (interval == "3m")) 
                           ||((stype nowstick == "low")&& (pr < minlasttwo+ 1/3*lasttwodiff)&& (lastonediff > 0.01) && (interval == "3m")) 

   let fifteenmindenyrulepredi = (stype nowstick == "low")&&(stype befstick == "low") && (interval == "15m")
                                                       -- if in 3mins ,any two sticks (max (bef,aft) - min (bef,aft) > 0.11,and check snds sticks,then prepare to buy)
  -- curpr( > high pr,return longer interval append position and 0) -  or (< low pr ,return -100000 ) 
  -- if (> low pr or < high pr,first to know near high or near low ,nearest point is (high-> mean to down ,quant should minus ) or (low-> mean to up  and return append position ) ,get up or low trend , then see small interval)
   --liftIO $ print (maxhigh,minlow)
   liftIO $ print (threeminrulepredi,fastup,fastdown ,bigpredi,havesndlowpredi,havesndhighpredi,waveveryfreq,smallpredi,fifteenmindenyrulepredi)
   case (threeminrulepredi,fastup,fastdown ,bigpredi,havesndlowpredi,havesndhighpredi,waveveryfreq,smallpredi,fifteenmindenyrulepredi) of 
        (True  ,_     ,_     ,_     ,_     ,_     ,_     ,_    ,_     ) ->  return ( (!!1) $ fromJust $  minrisksheet!?interval) -- up 
        (False ,True  ,False ,_     ,_     ,_     ,_     ,_    ,_     ) ->  return ( (!!0) $ fromJust $  minrisksheet!?interval) -- up fast
        (False ,False ,True  ,_     ,_     ,_     ,_     ,_    ,_     ) ->  return ( (!!3) $ fromJust $  minrisksheet!?interval) -- down fast
        (False ,False ,False ,False ,False ,True  ,False ,_    ,_     ) ->  return ( (!!2) $ fromJust $  minrisksheet!?interval) -- normal () down  max high is near, no snd low point, have snd high point,
        (False ,False ,False ,False ,True  ,False ,False ,True ,False ) ->  return ( (!!1) $ fromJust $  minrisksheet!?interval) -- normal () up    max high is near, have snd low point, no snd high point,
        (False ,False ,False ,False ,True  ,False ,False ,True ,True  ) ->  return ( (!!2) $ fromJust $  minrisksheet!?interval) -- normal () up    max high is near, have snd low point, no snd high point,
        (False ,False ,False ,True  ,True  ,False ,False ,True ,False ) ->  return ( (!!1) $ fromJust $  minrisksheet!?interval) -- normal () up    min low is near, have snd low point, no snd high point,
        (False ,False ,False ,True  ,False ,True  ,False ,_    ,_     ) ->  return ( (!!2) $ fromJust $  minrisksheet!?interval) -- normal () down  min low is near, no snd low point, have snd high point,
        (False ,False ,False ,_     ,True  ,True  ,True  ,True ,_     ) ->  return ( (!!1) $ fromJust $  minrisksheet!?interval) -- normal () up
        (False ,False ,False ,_     ,True  ,True  ,True  ,False,_     ) ->  return ( (!!2) $ fromJust $  minrisksheet!?interval) -- normal() down
        (False ,False ,False ,True  ,False ,False ,False ,_    ,_     ) ->  return ( (!!1) $ fromJust $  minrisksheet!?interval) -- normal () up min low is near,
        (False ,False ,False ,False ,False ,False ,False ,_    ,_     ) ->  return ( (!!2) $ fromJust $  minrisksheet!?interval) -- normal () down
        (False ,_     ,_     ,_     ,_     ,_     ,_     ,_    ,_     ) ->  return ( (!!2) $ fromJust $  minrisksheet!?interval) -- normal ()
   


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
                                        let highsheet = [((hprice $ fst x),snd x)| x<- xlist,((hprice $ fst x) > 0.1)  && ((stype $ fst x) == "high")] where xlist = reslist
                                        let lowsheet = [((lprice $ fst x),snd x)| x<-xlist ,((lprice $ fst x) > 0.1)  && ((stype $ fst x) == "low")] where xlist = reslist
                                        let highgrid = DT.foldr (\(l,h) y -> if (l == (max l (fst y))) then (l,h) else y ) (highsheet!!0) highsheet
                                        let lowgrid  = DT.foldr (\(l,h) y -> if (l == (min l (fst y))) then (l,h) else y ) (lowsheet!!0)  lowsheet 
                                        let highpr = fst highgrid 
                                        let lowpr = fst lowgrid 
                                        let diff = highpr - lowpr
                                        let wavediffpredi = (abs (highpr - lowpr ) <=0.005)
                                        let hlpredi = (snd highgrid) > (snd lowgrid)
                                        let prlocpredi = (currentpr < (highpr-diff*0.33)) && (currentpr >= (lowpr+diff/6))
                                        let lastjumppredi = (stype (rehllist!!0)=="low") && (stype (rehllist!!1)=="high") && (abs ((lprice $ rehllist!!0) -( hprice $ rehllist!!1))) > 0.01 
                                        liftIO $ print (highpr,lowpr,wavediffpredi,hlpredi,prlocpredi,lastjumppredi)
                                        case (wavediffpredi,hlpredi,prlocpredi,lastjumppredi) of 
                                            (True,_,_,_)-> return (-10000) 
                                            (False,True,True,False)-> return 70 
                                            (False,_,_,True)-> return 150
                                            (False,_,_,_)-> return (-10000)
                             LT -> return (-1000000)  
                             EQ -> return (-1000000)
