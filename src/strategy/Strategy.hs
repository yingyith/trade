{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
module Strategy
    ( 
     secondrule,
     minrule,
     genehighlowsheet,
     minrisksheet,
     crossminstra
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
import Data.Ord
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
import Lib
import Colog (LogAction,logByteStringStdout)
import Logger


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
                 ("3m" , [-20,  90,  -120, -180  ]), --first is up fast ,second is normal up,third is normal down ,forth is  fast down
                 ("5m" , [-20,  90,  -120, -180 ]), --
                 ("15m", [10 ,  90,  -120, -180 ]),
                 ("1h" , [15 ,  90,  -120, -180 ]),
                 ("4h" , [5  ,  90,  -120, -180 ]),
                 ("12h", [5  ,  90,  -120, -180  ]),
                 ("3d" , [5  ,  90,  -120, -180  ])
               ]

crossminstra :: [((Int,Double),(String,Int))] -> Double -> IO (Int,Double)
crossminstra abc pr = do 
    --3m ,5m,15m,1h,4h  if all up ,then double up 
    --3m ,5m,15m,1h,4h  if all down ,then double down 
    --accroding to the continuous kline ,the largest interval go against others is the risk number(append rule)
  --find  the near "up" "uf" "do" "df"
  --find the largest weight factor line ,use this line to set the benefit price 
    let uppredi  = (== 'u').(!!0) . fst .snd  
    -- get the continuous longest up interval ,
    let lhsheet = DT.map uppredi abc
    let trueresl = DL.group lhsheet --[true,false,true ,false]
    let grouplist = DT.map length trueresl
    let maxindex = snd $ maximumBy (comparing fst) (zip grouplist [0..]) 
    let item = trueresl  !! maxindex
    let itemindex = sum $ DT.take (maxindex-1) grouplist
    let itemlen = DT.length item
    let remainlist = (DT.drop (maxindex+itemlen) abc) ++ (DT.take maxindex abc ) 
    let itempredi = (itemlen <= 1)
    let itemipredi = (itemindex>3)

    let grid = (* 0.17) $ fromIntegral  $ snd $ snd $ (!! maxindex) abc :: Double  --transfer this grid to the redis order record can be used as 
    logact logByteStringStdout $ B.pack $ show (trueresl,maxindex,"cross def")
    case (itempredi,itemipredi) of 
          (True , _   )   -> return ((sum  [fst $ fst x|x<-abc]),grid)
          (False,True )   -> return ((sum  [fst $ fst x|x<-abc]),grid) 
          (False,False)   -> return (((sum [fst $ fst x| x<-remainlist]) +(sum [fst $ fst  x|x<-(DT.drop maxindex $  DT.take (maxindex+itemlen) abc )])*2 ),grid)
                                          

genehighlowsheet :: Int -> [BL.ByteString] -> String -> IO AS.Hlnode
genehighlowsheet index hl key = do 
    --liftIO $ print "____________hlsheet--------"
    --liftIO $ print hl

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
                  (True,True)   ->  (AS.Hlnode curitemt 0         curitemlp     0 "low"    key curitemcp)
                  (False,False) ->  (AS.Hlnode curitemt curitemhp 0             0 "high"   key curitemcp)
                  (False,True)  ->  (AS.Hlnode curitemt curitemhp curitemlp     0 "wbig"   key curitemcp)
                  (True,False)  ->  (AS.Hlnode curitemt 0         0             0 "wsmall" key curitemcp)
    --liftIO $ print "____________hlsheet--------"
    return res

minrule :: [AS.Hlnode]-> Double-> String  -> IO ((Int,Double),(String,Int))
minrule ahll pr interval  = do 
   let ahl = DT.take 10 ahll
   -- get max (high)
   -- get min (low)
   -- confirm nearest (high or low)
   -- return this grid risk
   -- confirm if last stick is low or high point ,their  last how many sticks,if low,then good to buy ,but need to know how man position,and close price
   --liftIO $ print ahl
   let reslist   =  [(xlist!!x,x)|x<-[1..(length xlist-2)],((stype $ xlist!!(x-1)) /= (stype $ xlist!!x)) && ((stype $ xlist!!x) /= "wsmall")] where xlist = ahl
   let reslistt   =  [(xlist!!x,x)|x<-[1..(length xlist-2)],((stype $ xlist!!(x-1)) /= (stype $ xlist!!x))] where xlist = ahl
   logact logByteStringStdout $ B.pack  ("enter min do ---------------------")
   let highsheet =  [((hprice $ fst x),snd x)| x<-xlist ,((hprice $ fst x) > 0.1)  && ((stype $ fst x) == "high")||((stype $ fst x) == "wbig")] where xlist = reslist
   let lowsheet  =  [((lprice $ fst x),snd x)| x<-xlist ,((lprice $ fst x) > 0.1)  && ((stype $ fst x) == "low") ||((stype $ fst x) == "wbig")] where xlist = reslist
   let hlbak     =  [((cprice $ fst x),snd x)| x<-xlist ,((cprice $ fst x) > 0.1)  && ((stype $ fst x) == "wsmall")] where xlist = reslistt
   
   
   --liftIO $ print (highsheet,lowsheet)
   let maxhigh   =   DT.foldr (\(l,h) y -> if (l == (max l (fst y))) then (l,h) else y )  (aim!!0) aim where aim = concat [lowsheet,hlbak,highsheet] 
   let minlow    =   DT.foldr (\(l,h) y -> if (l == (min l (fst y))) then (l,h) else y )  (aim!!0) aim where aim = concat [highsheet,hlbak,lowsheet] 
   logact logByteStringStdout $ B.pack $ show (ahl,highsheet,lowsheet,hlbak,maxhigh,minlow)
   let nowstick   =  ahl!!0
   let befstick   =  ahl!!1
   --if now stick is lowest point ,then down fast.not open in 3m and 15m, in 1hour and more other ,should half their up
   --if previous stick is lowest point,and rsi fit,then up 
   --if now stick is highest point , then up fast.not open
   --if previous stick is highest point,and rsi fit,then down 
   --if curpr > 3/4 grid < 7/8 ,is 1/4 up position  ,up      ,if rsi match then add 1/4 up 
   --if curpr < 1/4 grid > 1/8 ,is 1/2 up position  ,down    ,if rsi match then add total up 
   --                           else ,return -10, is notknown,if rsi match then add 1/2 up                
   let bigpredi         =  (snd maxhigh)      >    (snd minlow) --true is low near
   let griddiff         =  (fst maxhigh)      -    (fst minlow)
   let fastuppredi      =  (0   ==   (snd maxhigh))
   let fastdownpredi    =  (0   ==   (snd minlow ))
   let fastprevuppredi  =  (1   ==   (snd maxhigh)) &&  (interval == "15m") --need 3m support 
   let fastprevdopredi  =  (1   ==   (snd minlow )) &&  (interval == "15m") --need 3m support
   let openpos          = case pr of 
                             x| x>  ((fst maxhigh)-1/8*griddiff)                                      -> 0.125
                             x| x>  ((fst maxhigh)-1/4*griddiff) && x<= ((fst maxhigh)-1/8*griddiff)  -> 0.25 
                             x| x>  ((fst maxhigh)-3/4*griddiff) && x<= ((fst maxhigh)-1/4*griddiff)  -> 0.5                                 
                             x| x>  ((fst maxhigh)-7/8*griddiff) && x<= ((fst maxhigh)-3/4*griddiff)  -> 1                                
                             x| x<= ((fst maxhigh)-7/8*griddiff)                                      -> 0.125                               


   let threeminrulepredi = ((stype nowstick == "low")&&(stype befstick == "low") && (pr < (fst minlow)+ 1/3*griddiff)&& ((lprice befstick)-pr) > 0.08) && (interval == "3m")

   rsiindexf <- getrsi ahl 8
   let indexlentwo = case (fst rsiindexf) of 
                           x| x<2 -> 9
                           _      -> 8
   rsiindexx <- getrsi ahl indexlentwo
   let rsiindex = fst rsiindexx
   let openrsipos       = case rsiindex of 
                             x| x>85                                                                  -> -480
                             x| x>75 && x<=85                                                         -> -230
                             x| x>60 && x<=75                                                         -> -180
                             x| x>50 && x<=60                                                         -> -120
                             x| x>40 && x<=50                                                         -> -60
                             x| x>28 && x<=40                                                         -> 20
                             x| x>18 && x<=28                                                         -> 60
                             x| x>12 && x<=18                                                         -> 120
                             x| x>5  && x<=12                                                          -> 240
                             x| x<=5                                                                  -> 360
                                                       -- if in 3mins ,any two sticks (max (bef,aft) - min (bef,aft) > 0.11,and check snds sticks,then prepare to buy)
  -- curpr( > high pr,return longer interval append position and 0) -  or (< low pr ,return -100000 ) 
  -- if (> low pr or < high pr,first to know near high or near low ,nearest point is (high-> mean to down ,quant should minus ) or (low-> mean to up  and return append position ) ,get up or low trend , then see small interval)
   --liftIO $ print (maxhigh,minlow,rsiindexx,openpos)
   logact logByteStringStdout $ B.pack  (show (maxhigh,minlow,rsiindexx,openpos))
   --liftIO $ print (threeminrulepredi,fastuppredi,fastdownpredi,fastprevuppredi,fastprevdopredi,bigpredi)
   logact logByteStringStdout $ B.pack  (show (threeminrulepredi,fastuppredi,fastdownpredi,fastprevuppredi,fastprevdopredi,bigpredi))
   case (threeminrulepredi,fastuppredi,fastdownpredi,fastprevuppredi,fastprevdopredi,bigpredi) of 
        (True  ,_     ,_     ,_     ,_     ,_     ) ->  return ((( (!!1) $ fromJust $  minrisksheet!?interval),griddiff),("up",rsiindex)) -- up 
        (False ,True  ,False ,_     ,_     ,_     ) ->  return ((( (!!0) $ fromJust $  minrisksheet!?interval),griddiff),("uf",rsiindex)) -- up fast
        (False ,False ,True  ,_     ,_     ,_     ) ->  return ((( (!!3) $ fromJust $  minrisksheet!?interval),griddiff),("df",rsiindex)) -- down fast
        (False ,False ,False ,True  ,False ,_     ) ->  return ((( (!!2) $ fromJust $  minrisksheet!?interval),griddiff),("do",rsiindex)) -- down fast
        (False ,False ,False ,False ,True  ,_     ) ->  return ((( (!!1) $ fromJust $  minrisksheet!?interval),griddiff),("up",rsiindex)) -- down fast
        (False ,False ,False ,False ,False ,True  ) ->  return (((round $  (* openpos) $ (+ openrsipos) $ fromIntegral $ (!!1) $ fromJust $  minrisksheet!?interval),griddiff),("up",rsiindex)) -- down fast
        (False ,False ,False ,False ,False ,False ) ->  return (((round $  (* openpos) $ (+ openrsipos) $ fromIntegral $ (!!2) $ fromJust $  minrisksheet!?interval),griddiff),("do",rsiindex)) -- down fast
        (False ,_     ,_     ,_     ,_     ,_     ) ->  return ((0,griddiff),("no",0)) -- down fast
   


gethlsheetsec :: Int -> [ Klinedata ] -> IO (AS.Hlnode)
gethlsheetsec index kll =  do 
    --- rule1: if last one stick < last low point , return  -unlimitKlinedata
  --    rule2: if near high point then not open,if near low point can open  ,
    --liftIO $ print ("debug hlsheet---------")
    let curitem  = kll !! index 
    let nextitem  = kll !! (index + 1) 
    let curitemt = ktime curitem
    let curitemcp = read $ kclose curitem  :: Double
    let nextitemcp = read $ kclose nextitem :: Double 
    let predication = (curitemcp - nextitemcp) 
    let res = case compare predication  0 of 
                  LT   ->  (AS.Hlnode curitemt 0 curitemcp 0 "low" "1s" curitemcp)
                  GT ->  (AS.Hlnode curitemt curitemcp 0 0 "high" "1s" curitemcp)
                  EQ ->  (AS.Hlnode curitemt curitemcp 0 0 "wsmall" "1s" curitemcp)
    return res


secondrule :: [Klinedata] -> IO Int
secondrule records = do 
                        rehllist <- mapM ((\s ->  gethlsheetsec s records) :: Int -> IO AS.Hlnode ) [0..15] :: IO [AS.Hlnode]
                        rsiindexx <- getrsi rehllist 14
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
                        let hlpredi = (snd highgrid) > (snd lowgrid)--leave unsolved
                        let prlocpredi = (currentpr < (highpr-diff*0.33)) && (currentpr >= (lowpr+diff/6))
                        let lastjumppredi = (stype (rehllist!!0)=="low") && (stype (rehllist!!1)=="high") && (abs ((lprice $ rehllist!!0) -( hprice $ rehllist!!1))) > 0.01 
                        --liftIO $ print ("rsi is----",highpr,lowpr,wavediffpredi,hlpredi,prlocpredi,lastjumppredi,rsiindexx)
                        --rsiindexres <-  getrsi rehllist 64
                        case (wavediffpredi,hlpredi,prlocpredi,lastjumppredi) of 
                            (True ,_    ,_    ,_    )-> return (-15) 
                            (False,True ,True ,False)-> return 70 
                            (False,_    ,_    ,True )-> return 250
                            (False,_    ,_    ,_    )-> return (-30)
