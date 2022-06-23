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
import Control.Concurrent.STM
import Myutils



minrisksheet :: DM.Map String [Int] 
minrisksheet = fromList [
                 ("3m" , [-10     ,  90,  -120, -180  ]), --first is up fast ,second is normal up,third is normal down ,forth is  fast down
                 ("5m" , [-20     ,  90,  -120, -180  ]), --
                 ("15m", [30      ,  90,  -120, -180  ]),
                 ("1h" , [5       ,  90,  -120, -180  ]),
                 ("4h" , [5       ,  90,  -120, -180  ]),
                 ("12h", [5       ,  90,  -120, -180  ]),
                 ("3d" , [5       ,  90,  -120, -180  ])
               ]

crossminstra :: [((Int,(Double,Double)),(String,Int))] -> Double -> IO (Int,Double)
crossminstra abc pr = do 
    let uppredi  = \x -> ((> 14) $ fst $ fst x) && ( (== 'u') $ (!!0) $ fst $ snd  x )
    let lhsheet = DT.map uppredi abc
    let trueresl = DL.group lhsheet --[true,false,true ,false]
    let grouplist = DT.map length trueresl
    let maxindex = snd $ maximumBy (comparing fst) (zip grouplist [0..]) 
    let item = trueresl  !! maxindex
    let itemindex = sum $ DT.take (maxindex-1) grouplist
    let itemlen = DT.length item
    let remainlist = (DT.drop (maxindex+itemlen) abc) ++ (DT.take maxindex abc ) 
    let itempredi = (itemlen >= 2)
    let resquan = (sum  [fst $ fst x|x<-abc])
    let resbquan = ((sum [fst $ fst x| x<-remainlist]) +(sum [fst $ fst  x|x<-(DT.drop maxindex $  DT.take (maxindex+itemlen) abc )])*2 )
    let fallklineindex = maxindex+itemlen-1
    let aindex = case fallklineindex of 
                    x|x>=4          -> 4
                    x|(x>=0 || x<4) -> x

    let resquanori = case fallklineindex of 
                      x|x==1        -> (quanlist !! 0)
                      x|x==2        -> (quanlist !! 1)
                      x|x==3        -> (quanlist !! 1)
                      x|x==4        -> (quanlist !! 2)
                      x|x==5        -> (quanlist !! 3)
                      x|x==6        -> (quanlist !! 4)
                      _             -> 0
    let gridspan = snd $ fst $ (!! (aindex)) abc   --transfer this grid to the redis order record can be used as 
    let fstminsupporttrendpred   = ( (== 'u') $ (!!0) $ fst $ snd  $ (!! (2)) abc )
    let sndminsupporttrendpred   = ( (== 'u') $ (!!0) $ fst $ snd  $ (!! (3)) abc )
    let thdminsupporttrendpred   = ( (== 'u') $ (!!0) $ fst $ snd  $ (!! (4)) abc )
    let forthminsupporttrendpred = ( (== 'u') $ (!!0) $ fst $ snd  $ (!! (5)) abc )
    let zerominsupporttrendpred  = ( (== 'u') $ (!!0) $ fst $ snd  $ (!! (1)) abc )
    let (fstminsupportpredi,sndminsupportpredi, thdminsupportpredi)  = case (fstminsupporttrendpred,sndminsupporttrendpred,thdminsupporttrendpred,forthminsupporttrendpred) of 
             (False,False,False,True )     -> ((>   360 ) $ fst $ fst $ (!! (2)) abc ,  (> -100) $ fst $ fst $ (!! (3)) abc,  (> 100 ) $ fst $ fst $ (!! (4)) abc ) 
             (False,False,False,False)     -> ((>   380 ) $ fst $ fst $ (!! (2)) abc ,  (> 380 ) $ fst $ fst $ (!! (3)) abc,  (> 380 ) $ fst $ fst $ (!! (4)) abc ) 
             (True ,True ,False,False)     -> ((>   160 ) $ fst $ fst $ (!! (2)) abc ,  (> 380 ) $ fst $ fst $ (!! (3)) abc,  (> 380 ) $ fst $ fst $ (!! (4)) abc ) 
             (True ,False,False,_    )     -> ((>   240 ) $ fst $ fst $ (!! (2)) abc ,  (> 380 ) $ fst $ fst $ (!! (3)) abc,  (> 380 ) $ fst $ fst $ (!! (4)) abc ) 
             (_    ,_    ,_    ,_    )     -> ((>=  -100 ) $ fst $ fst $ (!! (2)) abc,  (> -260) $ fst $ fst $ (!! (3)) abc,  (> -250) $ fst $ fst $ (!! (4)) abc ) 
    let grid = 0.2* ((fst gridspan) - (snd gridspan))
    let lowp = snd gridspan
    let lowpredi = pr < (lowp + grid)
    let fallkline = (!!fallklineindex) abc 
    let openpredi = itempredi && fstminsupportpredi && sndminsupportpredi && thdminsupportpredi && zerominsupporttrendpred
    let stopprofitgrid = case fallklineindex of 
                              x|x==1        -> (stopprofitlist !! 0)
                              x|x==2        -> (stopprofitlist !! 1)
                              x|x==3        -> (stopprofitlist !! 2)
                              x|x==4        -> (stopprofitlist !! 2)
                              x|x==5        -> (stopprofitlist !! 2)
                              x|x==6        -> (stopprofitlist !! 2)
                              _             -> 0.0004
                            
    let basegrid = max (grid - (pr-lowp)) stopprofitgrid
    --let newgrid = stopprofitgrid 
    let (resquan,newgrid)  = case (fstminsupporttrendpred,sndminsupporttrendpred,thdminsupporttrendpred) of 
                          (False,False,False) -> ((minrulesheet!!0), 5*basegrid)
                          (False,False,True ) -> ((minrulesheet!!2),   basegrid)
                          (False,True ,True ) -> (resquanori       ,   basegrid)
                          (False,True ,False) -> ((minrulesheet!!1),   basegrid)
                          (True ,False,False) -> ((minrulesheet!!0), 2*basegrid) 
                          (True ,False,True ) -> ((minrulesheet!!2), 2*basegrid) 
                          (True ,True ,False) -> ((minrulesheet!!1), 5*basegrid) 
                          (True ,True ,True ) -> (resquanori       ,   basegrid)
    liftIO $ logact logByteStringStdout $ B.pack $ show ("minrule is---",resquanori,abc,itempredi,lowpredi,fstminsupportpredi,sndminsupporttrendpred,thdminsupportpredi,aindex,itempredi)
    case (openpredi) of 
          True    -> return (resquan,newgrid)
          False   -> return (resquan,newgrid) 
          --False   -> return ((min 0 resbquan) ,newgrid) 
        --(False,False)   -> return (((sum [fst $ fst x| x<-remainlist]) +(sum [fst $ fst  x|x<-(DT.drop maxindex $  DT.take (maxindex+itemlen) abc )])*2 ),grid)
   -- return (130,0.0005)
                                          

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
                  (True,True)   ->  (AS.Hlnode curitemt 0         curitemlp     0 "low"    key curitemcp)
                  (False,False) ->  (AS.Hlnode curitemt curitemhp 0             0 "high"   key curitemcp)
                  (False,True)  ->  (AS.Hlnode curitemt curitemhp curitemlp     0 "wbig"   key curitemcp)
                  (True,False)  ->  (AS.Hlnode curitemt 0         0             0 "wsmall" key curitemcp)
    return res

minrule :: [AS.Hlnode]-> Double-> String  -> IO ((Int,(Double,Double)),(String,Int))
minrule ahll pr interval  = do 
   let ahl = DT.take 11 ahll

   let reslist   =  [(xlist!!x,x)|x<-[0..(length xlist-2)]] where xlist = ahl
   --logact logByteStringStdout $ B.pack  ("enter min do ---------------------")
   let highsheet =  [((hprice $ fst x),snd x)| x<-xlist ,((hprice $ fst x) > 0.1)  && ((stype $ fst x) == "high")||((stype $ fst x) == "wbig")] where xlist = reslist
   let lowsheet  =  [((lprice $ fst x),snd x)| x<-xlist ,((lprice $ fst x) > 0.1)  && ((stype $ fst x) == "low") ||((stype $ fst x) == "wbig")] where xlist = reslist
   let hlbak     =  [((cprice $ fst x),snd x)| x<-xlist ,((cprice $ fst x) > 0.1)  ] where xlist = reslist
   let maxhigh   =   DT.foldr (\(l,h) y -> if (l == (max l (fst y))) then (l,h) else y )  (aim!!0) aim where aim = concat [lowsheet,hlbak,highsheet] 
   let minlow    =   DT.foldr (\(l,h) y -> if (l == (min l (fst y))) then (l,h) else y )  (aim!!0) aim where aim = concat [highsheet,hlbak,lowsheet] 
   --logact logByteStringStdout $ B.pack $ show ("index show==========",highsheet,lowsheet,hlbak,maxhigh,minlow)
   let nowstick   =  ahl!!0
   let befstick   =  ahl!!1
   let bigpredi         =  (snd maxhigh)      >    (snd minlow) --true is low near
   let gridspan         = ( (fst maxhigh) ,(fst minlow))
   let griddiff         = (fst maxhigh)-(fst minlow)
   let fastuppredi      =  (0   >=   (snd maxhigh)) 
   let fastdownpredi    =  (0   >=   (snd minlow ))
   let fastprevuppredi  =  (1   ==   (snd maxhigh))  --need 3m support 
   let fastprevdopredi  =  (1   ==   (snd minlow ))  --need 3m support
   let openpos          = case pr of 
                             x| x>  ((fst maxhigh)-1/8*griddiff)                                      -> 0.01
                             x| x>  ((fst maxhigh)-1/4*griddiff) && x<= ((fst maxhigh)-1/8*griddiff)  -> 0.1
                             x| x>  ((fst maxhigh)-3/4*griddiff) && x<= ((fst maxhigh)-1/4*griddiff)  -> 0.2                                 
                             x| x>  ((fst maxhigh)-7/8*griddiff) && x<= ((fst maxhigh)-3/4*griddiff)  -> 1                                
                             x| x<= ((fst maxhigh)-7/8*griddiff)                                      -> 0.5                             
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
                             x| x>28 && x<=40                                                         ->  20
                             x| x>18 && x<=28                                                         ->  60
                             x| x>12 && x<=18                                                         ->  120
                             x| x>8  && x<=12                                                         ->  240
                             x| x>5  && x<=8                                                          ->  360
                             x| x>2  && x<=5                                                          ->  480
                             x| x<=2                                                                  ->  600

   --logact logByteStringStdout $ B.pack  (show (maxhigh,minlow,rsiindexx,openpos))
   --logact logByteStringStdout $ B.pack  (show (threeminrulepredi,fastuppredi,fastdownpredi,fastprevuppredi,fastprevdopredi,bigpredi))
   case (threeminrulepredi,fastuppredi,fastdownpredi,fastprevuppredi,fastprevdopredi,bigpredi) of 
        (True  ,_     ,_     ,_     ,_     ,_     ) ->  return ((( (!!1) $ fromJust $  minrisksheet!?interval),gridspan),("up",rsiindex)) -- up 
        (False ,True  ,False ,_     ,_     ,_     ) ->  return ((( (!!0) $ fromJust $  minrisksheet!?interval),gridspan),("uf",rsiindex)) -- up fast
        (False ,False ,True  ,_     ,_     ,_     ) ->  return ((( (!!3) $ fromJust $  minrisksheet!?interval),gridspan),("df",rsiindex)) -- down fast
        (False ,False ,False ,True  ,False ,_     ) ->  return ((( (!!2) $ fromJust $  minrisksheet!?interval),gridspan),("do",rsiindex)) -- down fast
        (False ,False ,False ,False ,True  ,_     ) ->  return ((( (!!1) $ fromJust $  minrisksheet!?interval),gridspan),("up",rsiindex)) -- down fast
        (False ,False ,False ,False ,False ,True  ) ->  return (((round $  (* openpos) $ (+ openrsipos) $ fromIntegral $ (!!1) $ fromJust $  minrisksheet!?interval),gridspan),("up",rsiindex)) -- down fast
        (False ,False ,False ,False ,False ,False ) ->  return (((round $  (* openpos) $ (+ openrsipos) $ fromIntegral $ (!!2) $ fromJust $  minrisksheet!?interval),gridspan),("do",rsiindex)) -- down fast
        (False ,_     ,_     ,_     ,_     ,_     ) ->  return ((0,gridspan),("no",0)) -- down fast
   


gethlsheetsec :: Int -> [ Klinedata ] -> IO (AS.Hlnode)
gethlsheetsec index kll =  do 
    let curitem     = kll !! index 
    let nextitem    = kll !! (index + 1) 
    let curitemt    = ktime curitem
    let curitemcp   = read $ kclose curitem  :: Double
    let nextitemcp  = read $ kclose nextitem :: Double 
    let predication = (curitemcp - nextitemcp) 
    let res = case compare predication  0 of 
                  LT   ->  (AS.Hlnode curitemt 0         curitemcp 0 "low"    "1s" curitemcp)
                  GT   ->  (AS.Hlnode curitemt curitemcp 0         0 "high"   "1s" curitemcp)
                  EQ   ->  (AS.Hlnode curitemt curitemcp 0         0 "wsmall" "1s" curitemcp)
    return res

getdiffgridnum :: (Double,Double)-> (Int,Double) 
getdiffgridnum  (a,b) = case (a>b) of 
                                  True  -> case res of 
                                      x|x<(diffspreadsheet!!1) && x>= (diffspreadsheet!!0)  ->( ( depthrisksheet !! 0),res) 
                                      x|x<(diffspreadsheet!!2) && x>= (diffspreadsheet!!1)  ->( ( depthrisksheet !! 1),res) 
                                      x|x<(diffspreadsheet!!3) && x>= (diffspreadsheet!!2)  ->( ( depthrisksheet !! 2),res)
                                      x|x<(diffspreadsheet!!4) && x>= (diffspreadsheet!!3)  ->( ( depthrisksheet !! 3),res)
                                      x|x<(diffspreadsheet!!5) && x>= (diffspreadsheet!!4)  ->( ( depthrisksheet !! 4),res)
                                      x|x<(diffspreadsheet!!6) && x>= (diffspreadsheet!!5)  ->( ( depthrisksheet !! 5),res)
                                      x|x<(diffspreadsheet!!7) && x>= (diffspreadsheet!!6)  ->( ( depthrisksheet !! 6),res)
                                      x|x>= (diffspreadsheet!!7)                            ->( ( depthrisksheet !! 6),res)
                                      _                                                     ->( 60,res)
                                  False -> case (abs res) of 
                                      x|x<(diffspreadsheet!!1) && x>= (diffspreadsheet!!0)  ->( -( depthrisksheet !! 0),res)
                                      x|x<(diffspreadsheet!!2) && x>= (diffspreadsheet!!1)  ->( -( depthrisksheet !! 1),res) 
                                      x|x<(diffspreadsheet!!3) && x>= (diffspreadsheet!!2)  ->( -( depthrisksheet !! 2),res)
                                      x|x<(diffspreadsheet!!4) && x>= (diffspreadsheet!!3)  ->( -( depthrisksheet !! 3),res)
                                      x|x<(diffspreadsheet!!5) && x>= (diffspreadsheet!!4)  ->( -( depthrisksheet !! 4),res)
                                      x|x<(diffspreadsheet!!6) && x>= (diffspreadsheet!!5)  ->( -( depthrisksheet !! 5),res)
                                      x|x<(diffspreadsheet!!7) && x>= (diffspreadsheet!!6)  ->( -( depthrisksheet !! 6),res)
                                      x|x>= (diffspreadsheet!!7)                            ->( -( depthrisksheet !! 6),res)
                                      _                                                     ->( -60,res)
                           where res  = (a-b)/(max a b)

                     --return (quan,res)

secondrule ::  [(Double,Double)]  -> IO (Int,Double)
secondrule ablist = do 
                     let ratiol = DT.map getdiffgridnum ablist
                     let resf = (ratiol !! 0)
                     let ress = (ratiol !! 1)
                     logact logByteStringStdout $ B.pack $ show ("baratiois--------","a"++(showdouble   $ snd resf        ),
                                                                                     "b"++(showdouble   $ snd ress        ),
                                                                                     "c"++(showdouble   $ snd (ratiol !!2)),
                                                                                     "aa"++(showdouble  $ snd (ratiol !!3)),
                                                                                     "bb"++(showdouble  $ snd (ratiol !!4)),
                                                                                     "cc"++(showdouble  $ snd (ratiol !!5)), 
                                                                                     "aaa"++(showdouble $ snd (ratiol !!6)),
                                                                                     "bbb"++(showdouble $ snd (ratiol !!7)),
                                                                                     "ccc"++(showdouble $ snd (ratiol !!8)),
                                                                                     "ddd"++(showdouble $ snd (ratiol !!9)),
                                                                                     "eee"++(showdouble $ snd (ratiol !!10)))
                     let totalquan = (fst resf)+(fst ress) 
                     let resquan = (fst resf)+ (fst ress)
                     return (resquan,max (snd resf) (snd ress))



