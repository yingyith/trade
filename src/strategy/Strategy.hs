{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
module Strategy
    ( 
     secondrule,
     minrule,
     genehighlowsheet,
     minrisksheet,
     crossminstra,
     volumn_stra_1m,
     needlestra
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
import Order
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
                 ("1d",  [5       ,  90,  -120, -180  ]),
                 ("3d" , [5       ,  90,  -120, -180  ]),
                 ("1w" , [5       ,  90,  -120, -180  ]),
                 ("1M" , [5       ,  90,  -120, -180  ])
               ]

crossminstra :: [(((Int,(Double,Double)),(String,Int)),[Hlnode])] -> Double -> IO ((Int,Int),(String,String))
crossminstra abcc pr = do 
    let abc = [fst i|i<-abcc] 
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
    let fstminsupporttrendpred     = ( (== 'u') $ (!!0) $ fst $ snd  $ (!! (2)) abc )
    let sndminsupporttrendpred     = ( (== 'u') $ (!!0) $ fst $ snd  $ (!! (3)) abc )
    let thdminsupporttrendpred     = ( (== 'u') $ (!!0) $ fst $ snd  $ (!! (4)) abc )
    let forthminsupporttrendpred   = ( (== 'u') $ (!!0) $ fst $ snd  $ (!! (5)) abc )
    let fiveminsupporttrendpred    = ( (== 'u') $ (!!0) $ fst $ snd  $ (!! (1)) abc )
    let threeminsupporttrendpred   = ( (== 'u') $ (!!0) $ fst $ snd  $ (!! (0)) abc )

    let grid = 0.2* ((fst gridspan) - (snd gridspan))
    let lowp = snd gridspan
    let lowpredi = pr < (lowp + grid)
    let fallkline = (!!fallklineindex) abc 
    let stopprofitgrid = case fallklineindex of 
                              x|x==1        -> (stopprofitlist !! 0)
                              x|x==2        -> (stopprofitlist !! 1)
                              x|x==3        -> (stopprofitlist !! 2)
                              x|x==4        -> (stopprofitlist !! 2)
                              x|x==5        -> (stopprofitlist !! 2)
                              x|x==6        -> (stopprofitlist !! 2)
                              _             -> 0.0004
    let latest_stick_15m      =   [snd i|i<-abcc] 
    --needle sharpe condition
    -- compare 15m kline with 1h kline, if highpoint (15m) == highpoint (1h) ,if latest_nodebef(15m) == lowpoint (15m) or curpr -lowpoint(15m) < 0.004,then not open buy 
    -- compare 15m kline with 1h kline, if lowpoint (15m) == lowpoint (1h) ,if latest_nodebef(15m) == highpoint (15m) or curpr -highpoint(15m) < 0.004,then not open sell 
    let lowpointtrendpred     = ((abs ((snd $ snd $  fst $ (!!2) abc) - (snd $ snd $  fst $ (!!3) abc))) <= 0.0025)
                                  && (((snd $ snd $  fst $ (!!1) abc) /= (snd $ snd $  fst $ (!!2) abc) ))
                                      

    let lowpointpredsmall     = ((pr-0.0015)< (snd $ snd $  fst $ (!!2) abc))

    let lowpointpredbig       = (((snd $ snd $  fst $ (!!1) abc)-0.002) < ((snd $ snd $  fst $ (!!3) abc)))   
                                  || ((pr-0.002)< (snd $ snd $  fst $ (!!3) abc))
                                  || lowpointtrendpred

    let highpointtrendpred    = ((abs ((fst $ snd $  fst $ (!!2) abc) - (fst $ snd $  fst $ (!!3) abc))) <= 0.0025)
                                  && (((fst $ snd $  fst $ (!!1) abc) /=  (fst $ snd $  fst $ (!!2) abc) ))
                                

    let highpointpredsmall    = ((pr+0.0015)> (fst $ snd $  fst $ (!!2) abc))

    let highpointpredbig      = (((fst $ snd $  fst $ (!!1) abc)+0.002) > ((fst $ snd $  fst $ (!!3) abc)))   
                                  || ((pr+0.002)> (fst $ snd $  fst $ (!!3) abc))
                                  || highpointtrendpred

    let (lowpointfactor,reasonlow)   = case (lowpointpredsmall,lowpointpredbig) of 
                            (True,True  )  -> (3000,"no")  --threshhold to short direction
                            (True,False )  -> (1200,"no") --threshhold to short direction
                            (False,True )  -> (3000,"no")  --threshhold to short direction
                            (False,False)  -> case (highpointpredsmall,highpointpredbig) of 
                                                    (True,False )  ->(1200,"no")  --threshhold to short direction
                                                    (True,True  )  ->(1200,"no")  --threshhold to short direction
                                                    (_   ,_     )  ->(0,"yes") 
    let (highpointfactor,reasonhigh) = case (highpointpredsmall,highpointpredbig) of 
                            (True,True  )  ->(3000,"no")  --threshhold to short direction
                            (True,False )  ->(1200,"no")  --threshhold to short direction
                            (False,True )  ->(3000,"no")  --threshhold to short direction
                            (False,False)  -> case (lowpointpredsmall,lowpointpredbig) of 
                                                    (True,False )  ->(1200,"no")  --threshhold to short direction
                                                    (True,True  )  ->(1200,"no")  --threshhold to short direction
                                                    (_   ,_     )  ->(0,"yes") 
                            
    let basegrid = max (grid - (pr-lowp)) stopprofitgrid
    let (mthresholdup,mthresholddo) = case (threeminsupporttrendpred ,fiveminsupporttrendpred,fstminsupporttrendpred) of 
                                  (True  ,True ,True  )  -> ((shortminrulethreshold !! 1),(shortminrulethreshold !!0 ))--both up ,hard for short
                                  (True  ,True ,False )  -> ((shortminrulethreshold !! 0),(shortminrulethreshold !!1 ))--both up ,hard for short
                                  (False ,True ,True  )  -> ((shortminrulethreshold !! 1),(shortminrulethreshold !!0 ))--have one down ,hard for long
                                  (False ,True ,False )  -> ((shortminrulethreshold !! 0),(shortminrulethreshold !!2 ))--have one down ,hard for long
                                  (True  ,False,True  )  -> ((shortminrulethreshold !! 2),(shortminrulethreshold !!0 ))--have one down ,hard for long
                                  (True  ,False,False )  -> ((shortminrulethreshold !! 0),(shortminrulethreshold !!1 ))--have one down ,hard for long
                                  (False ,False,True  )  -> ((shortminrulethreshold !! 1),(shortminrulethreshold !!0 ))--have two down ,hard for long
                                  (False ,False,False )  -> ((shortminrulethreshold !! 0),(shortminrulethreshold !!1 ))--have two down ,hard for long
    --let newgrid = stopprofitgrid 
    let (hthresholdup,hthresholddo)  = case (fstminsupporttrendpred,sndminsupporttrendpred,thdminsupporttrendpred) of 
                          (False,False,False) ->  ((minrulethreshold!!0),(minrulethreshold!!1))     -- left for hard degree of UP,right for hard degree of DOWN
                          (True ,False,False) ->  ((minrulethreshold!!0),(minrulethreshold!!2))   
                          (False,True ,False) ->  ((minrulethreshold!!2),(minrulethreshold!!1))  
                          (True ,True ,False) ->  ((minrulethreshold!!3),(minrulethreshold!!0))   
                          (False,False,True ) ->  ((minrulethreshold!!0),(minrulethreshold!!3))
                          (True ,False,True ) ->  ((minrulethreshold!!1),(minrulethreshold!!2))  
                          (False,True ,True ) ->  ((minrulethreshold!!2),(minrulethreshold!!0)) 
                          (True ,True ,True ) ->  ((minrulethreshold!!1),(minrulethreshold!!0)) 

    let totalthresholdup = mthresholdup + hthresholdup
    let totalthresholddo = mthresholddo + hthresholddo
    liftIO $ logact logByteStringStdout $ B.pack $ show ("minrule is---",totalthresholdup,totalthresholddo,abc,lowpointtrendpred,highpointtrendpred)
    return ((totalthresholdup+highpointfactor,totalthresholddo+lowpointfactor),(reasonhigh,reasonlow))
                                          
needlestra:: [(((Int,(Double,Double)),(String,Int)),[Hlnode])] -> IO  ((Bool,AS.Trend),String) 
needlestra  abcc  = do
    let abck                      =        [fst i|i<-abcc] 
    let abc                       =        [snd i|i<-abcc] 
    let lkline_15m                =        (!!1) $ (!!2) abc
    let lbokline_15m              =        (!!2) $ (!!2) abc
    let hl_1h                     =        (snd $  fst $ (!!3) abck)
    let hl_4h                     =        (snd $  fst $ (!!4) abck)
    let hl_4h_fnode               =        (!!0) $ (!!4) abc
    let hl_4h_snode               =        (!!1) $ (!!4) abc
    let hl_4h_snode_hprice        =        hprice hl_4h_snode
    let hl_4h_snode_lprice        =        lprice hl_4h_snode
    let (ah,al,ac,ao)             =        ((hprice lkline_15m  ),(lprice lkline_15m  ),(cprice lkline_15m  ),(cprice lbokline_15m)) 
    let (bh,bl,bc)                =        ((hprice lbokline_15m),(lprice lbokline_15m),(cprice lbokline_15m)) 
    let (ad1,ad2)                 =        (abs (ah-(max ao ac)),abs (al-(min ao ac)))
    let needlelenpred             =        (>=0.0025)  $ max ad1 ad2        
    let hdelay_4h_fulfil_pred     =        hl_4h_snode_hprice == (fst hl_4h)
    let ldelay_4h_fulfil_pred     =        hl_4h_snode_lprice == (snd hl_4h)

    let (hcropred,hrea,hside)     =        case (((<0.0015)  (abs  (bh-(fst hl_1h)))) ,hdelay_4h_fulfil_pred && ((<0.003)  (abs  (bh-(fst hl_4h))))) of 
                                               (False,False) -> (False,"0m" ,AS.DO) 
                                               (False,True ) -> (True ,"4h" ,AS.DO) 
                                               (True ,False) -> (True ,"1h", AS.DO)
                                               (True ,True ) -> (True ,"4h" ,AS.DO)

    let (lcropred,lrea,lside)     =        case (((<0.0015)  (abs  (bl-(snd hl_1h)))) ,ldelay_4h_fulfil_pred &&((<0.003)  (abs  (bl-(snd hl_4h))))) of 
                                               (False,False) -> (False,"0m" ,AS.UP) 
                                               (False,True ) -> (True ,"4h" ,AS.UP) 
                                               (True ,False) -> (True ,"1h", AS.UP)
                                               (True ,True ) -> (True ,"4h" ,AS.UP)

    let (needlepredd,rea,side)    =        case (hcropred,lcropred) of 
                                               (False,False) -> (False,"0m" , AS.UP)
                                               (True ,False) -> (True ,hrea , hside)
                                               (False,True ) -> (True ,lrea , lside)
                                               (True ,True ) -> (True ,"0m" , AS.UP)

    let needlerpred               =        needlelenpred && needlepredd 
    liftIO $ logact logByteStringStdout $ B.pack $ show ("needle is---",lkline_15m,needlerpred,rea)
    return ((needlerpred,side),rea)
     

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
                 -- (True,True)   ->  (AS.Hlnode curitemt 0         curitemlp     0 "low"    key curitemcp)
                 -- (False,False) ->  (AS.Hlnode curitemt curitemhp 0             0 "high"   key curitemcp)
                 -- (False,True)  ->  (AS.Hlnode curitemt curitemhp curitemlp     0 "wbig"   key curitemcp)
                 -- (True,False)  ->  (AS.Hlnode curitemt 0         0             0 "wsmall" key curitemcp)
                  (True,True)   ->  (AS.Hlnode curitemt curitemhp curitemlp     0 "low"    key curitemcp)
                  (False,False) ->  (AS.Hlnode curitemt curitemhp curitemlp     0 "high"   key curitemcp)
                  (False,True)  ->  (AS.Hlnode curitemt curitemhp curitemlp     0 "wbig"   key curitemcp)
                  (True,False)  ->  (AS.Hlnode curitemt curitemhp curitemlp     0 "wsmall" key curitemcp)
    return res

minrule :: [AS.Hlnode]-> Double-> String  -> IO ((Int,(Double,Double)),(String,Int))
minrule ahll pr interval  = do 
   let alength = case interval of 
                    "3m" -> 7
                    "5m" -> 7
                    "4h" -> 14
                    "1w" -> 14
                    _    -> 11
   let ahl = DT.take alength ahll
   let reslist   =  [(xlist!!x,x)|x<-[0..(length xlist-2)]] where xlist = ahl
   --logact logByteStringStdout $ B.pack  ("enter min do ---------------------")
   let highsheet =  [((hprice $ fst x),snd x)| x<-xlist ,((hprice $ fst x) > 0.1)  && ((stype $ fst x) == "high")||((stype $ fst x) == "wbig")] where xlist = reslist
   let lowsheet  =  [((lprice $ fst x),snd x)| x<-xlist ,((lprice $ fst x) > 0.1)  && ((stype $ fst x) == "low") ||((stype $ fst x) == "wbig")] where xlist = reslist
   let hlbak     =  [((cprice $ fst x),snd x)| x<-xlist ,((cprice $ fst x) > 0.1)  ] where xlist = reslist
   let maxhigh   =   DT.foldr (\(l,h) y -> if (l == (max l (fst y))) then (l,h) else y )  (aim!!0) aim where aim = concat [lowsheet,hlbak,highsheet] 
   let minlow    =   DT.foldr (\(l,h) y -> if (l == (min l (fst y))) then (l,h) else y )  (aim!!0) aim where aim = concat [highsheet,hlbak,lowsheet] 
   --logact logByteStringStdout $ B.pack $ show ("index show==========",highsheet,lowsheet,hlbak,maxhigh,minlow,reslist)
   let nowstick   =  ahl!!0
   let befstick   =  ahl!!1
   let bigpredi         =  (snd maxhigh)      >    (snd minlow) --true is low near
   let gridspan         =  ((fst maxhigh) ,(fst minlow))
   let griddiff         =  (fst maxhigh)-(fst minlow)
   let fastprevuppredi  =  (3   >=   (snd maxhigh))  --need 3m support 
   let fastprevdopredi  =  (3   >=   (snd minlow ))  --need 3m support
   let openpos          = case pr of 
                             x| x>  ((fst maxhigh)-1/8*griddiff)                                      -> 0.01
                             x| x>  ((fst maxhigh)-1/4*griddiff) && x<= ((fst maxhigh)-1/8*griddiff)  -> 0.1
                             x| x>  ((fst maxhigh)-3/4*griddiff) && x<= ((fst maxhigh)-1/4*griddiff)  -> 0.2                                 
                             x| x>  ((fst maxhigh)-7/8*griddiff) && x<= ((fst maxhigh)-3/4*griddiff)  -> 1                                
                             x| x<= ((fst maxhigh)-7/8*griddiff)                                      -> 0.5                             
   rsiindexf <- getrsi ahl 6
   let indexlentwo = case (fst rsiindexf) of 
                           x| x<2 -> 7
                           _      -> 7
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

   case (fastprevuppredi,fastprevdopredi,bigpredi) of 
        (True  ,False ,_     ) ->  return ((( (!!2) $ fromJust $  minrisksheet!?interval),gridspan),("uf",rsiindex)) -- down fast
        (False ,True  ,_     ) ->  return ((( (!!1) $ fromJust $  minrisksheet!?interval),gridspan),("df",rsiindex)) -- down fast
        (False ,False ,True  ) ->  return ((0,gridspan),("up",rsiindex)) -- also need to see diff to low point , 
        (False ,False ,False ) ->  return ((0,gridspan),("do",rsiindex)) -- down fast
        (True  ,True  ,True  ) ->  return ((0,gridspan),("up",rsiindex)) -- down fast
        (True  ,True  ,False ) ->  return ((0,gridspan),("do",rsiindex)) -- down fast
   


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
                                  True  -> case (abs res) of  --bid > ask  up
                                      x|x<(diffspreadsheet!!1) && x>= (diffspreadsheet!!0)  ->(( depthrisksheet !! 0),res) 
                                      x|x<(diffspreadsheet!!2) && x>= (diffspreadsheet!!1)  ->(( depthrisksheet !! 1),res) 
                                      x|x<(diffspreadsheet!!3) && x>= (diffspreadsheet!!2)  ->(( depthrisksheet !! 2),res)
                                      x|x<(diffspreadsheet!!4) && x>= (diffspreadsheet!!3)  ->(( depthrisksheet !! 3),res)
                                      x|x<(diffspreadsheet!!5) && x>= (diffspreadsheet!!4)  ->(( depthrisksheet !! 4),res)
                                      x|x<(diffspreadsheet!!6) && x>= (diffspreadsheet!!5)  ->(( depthrisksheet !! 5),res)
                                      x|x<(diffspreadsheet!!7) && x>= (diffspreadsheet!!6)  ->(( depthrisksheet !! 6),res)
                                      x|x<(diffspreadsheet!!8) && x>= (diffspreadsheet!!7)  ->(( depthrisksheet !! 7),res)
                                      _                                                     ->(( depthrisksheet !! 0),res)
                                  False -> case (abs res) of 
                                      x|x<(diffspreadsheet!!1) && x>= (diffspreadsheet!!0)  ->(-( depthrisksheet !! 0),res)
                                      x|x<(diffspreadsheet!!2) && x>= (diffspreadsheet!!1)  ->(-( depthrisksheet !! 1),res) 
                                      x|x<(diffspreadsheet!!3) && x>= (diffspreadsheet!!2)  ->(-( depthrisksheet !! 2),res)
                                      x|x<(diffspreadsheet!!4) && x>= (diffspreadsheet!!3)  ->(-( depthrisksheet !! 3),res)
                                      x|x<(diffspreadsheet!!5) && x>= (diffspreadsheet!!4)  ->(-( depthrisksheet !! 4),res)
                                      x|x<(diffspreadsheet!!6) && x>= (diffspreadsheet!!5)  ->(-( depthrisksheet !! 5),res)
                                      x|x<(diffspreadsheet!!7) && x>= (diffspreadsheet!!6)  ->(-( depthrisksheet !! 6),res)
                                      x|x<(diffspreadsheet!!8) && x>= (diffspreadsheet!!7)  ->(-( depthrisksheet !! 7),res)
                                      _                                                     ->(-( depthrisksheet !! 0),res)
                           where res  = ((a-b)/(max a b))

waveonlongsight :: Double -> Double -> Double -> AS.Trend -> Int
waveonlongsight  ccc   ddd eee  trend = do
           case (ccc>0,trend) of 
                 (True, AS.UP)  ->  case ccc of 
                                       x|x< (adjustratiosheet!!1) &&  x>=(adjustratiosheet!!0)   -> fst $  (adjustboostgrid!!0)
                                       x|x< (adjustratiosheet!!2) &&  x>=(adjustratiosheet!!1)   -> fst $  (adjustboostgrid!!1)
                                       x|x< (adjustratiosheet!!3) &&  x>=(adjustratiosheet!!2)   -> fst $  (adjustboostgrid!!2)
                                       x|x< (adjustratiosheet!!4) &&  x>=(adjustratiosheet!!3)   -> fst $  (adjustboostgrid!!3)
                                       x|x< (adjustratiosheet!!5) &&  x>=(adjustratiosheet!!4)   -> fst $  (adjustboostgrid!!4)
                                       x|x< (adjustratiosheet!!6) &&  x>=(adjustratiosheet!!5)   -> fst $  (adjustboostgrid!!5)
                                       x|x< (adjustratiosheet!!7) &&  x>=(adjustratiosheet!!6)   -> fst $  (adjustboostgrid!!6)
                                       _                                                         -> fst $  (adjustboostgrid!!0) 
                 (True, AS.DO)  ->  case ccc of 
                                       x|x< (adjustratiosheet!!1) &&  x>=(adjustratiosheet!!0)   -> (snd $  (adjustboostgrid!!0)) 
                                       x|x< (adjustratiosheet!!2) &&  x>=(adjustratiosheet!!1)   -> (snd $  (adjustboostgrid!!1))
                                       x|x< (adjustratiosheet!!3) &&  x>=(adjustratiosheet!!2)   -> (snd $  (adjustboostgrid!!2))
                                       x|x< (adjustratiosheet!!4) &&  x>=(adjustratiosheet!!3)   -> (snd $  (adjustboostgrid!!3))
                                       x|x< (adjustratiosheet!!5) &&  x>=(adjustratiosheet!!4)   -> (snd $  (adjustboostgrid!!4))
                                       x|x< (adjustratiosheet!!6) &&  x>=(adjustratiosheet!!5)   -> (snd $  (adjustboostgrid!!5))
                                       x|x< (adjustratiosheet!!7) &&  x>=(adjustratiosheet!!6)   -> (snd $  (adjustboostgrid!!6))
                                       _                                                         -> (snd $  (adjustboostgrid!!0)) 
                 (False,AS.UP)  ->  case (abs ccc) of 
                                       x|x< (adjustratiosheet!!1) &&  x>=(adjustratiosheet!!0)   -> -(snd $  (adjustboostgrid!!0))
                                       x|x< (adjustratiosheet!!2) &&  x>=(adjustratiosheet!!1)   -> -(snd $  (adjustboostgrid!!1))
                                       x|x< (adjustratiosheet!!3) &&  x>=(adjustratiosheet!!2)   -> -(snd $  (adjustboostgrid!!2))
                                       x|x< (adjustratiosheet!!4) &&  x>=(adjustratiosheet!!3)   -> -(snd $  (adjustboostgrid!!3))
                                       x|x< (adjustratiosheet!!5) &&  x>=(adjustratiosheet!!4)   -> -(snd $  (adjustboostgrid!!4))
                                       x|x< (adjustratiosheet!!6) &&  x>=(adjustratiosheet!!5)   -> -(snd $  (adjustboostgrid!!5))
                                       x|x< (adjustratiosheet!!7) &&  x>=(adjustratiosheet!!6)   -> -(snd $  (adjustboostgrid!!6))
                                       _                                                         -> -(snd $  (adjustboostgrid!!0)) 
                 (False,AS.DO)  ->  case (abs ccc) of 
                                       x|x< (adjustratiosheet!!1) &&  x>=(adjustratiosheet!!0)   -> -(fst $  (adjustboostgrid!!0))
                                       x|x< (adjustratiosheet!!2) &&  x>=(adjustratiosheet!!1)   -> -(fst $  (adjustboostgrid!!1))
                                       x|x< (adjustratiosheet!!3) &&  x>=(adjustratiosheet!!2)   -> -(fst $  (adjustboostgrid!!2))
                                       x|x< (adjustratiosheet!!4) &&  x>=(adjustratiosheet!!3)   -> -(fst $  (adjustboostgrid!!3))
                                       x|x< (adjustratiosheet!!5) &&  x>=(adjustratiosheet!!4)   -> -(fst $  (adjustboostgrid!!4))
                                       x|x< (adjustratiosheet!!6) &&  x>=(adjustratiosheet!!5)   -> -(fst $  (adjustboostgrid!!5))
                                       x|x< (adjustratiosheet!!7) &&  x>=(adjustratiosheet!!6)   -> -(fst $  (adjustboostgrid!!6))
                                       _                                                         -> -(fst $  (adjustboostgrid!!0)) 
                 (_   ,_     )  ->  0

volumn_stra_1m :: AS.Klines_1 -> Double    -> IO  ((Bool,AS.Trend),String)
volumn_stra_1m kline_1 dcp  = do
                     let klines_1ms           =      AS.klines_1m kline_1
                     let klines_1sset_va      =      AS.klines_1s kline_1
                     let klines_1sset_va_1    =      knpamount $  (!!1) $ klines_1sset_va
                     let klines_1sset_va_2    =      knpamount $  (!!2) $ klines_1sset_va
                     let klines_1sset_va_d    =      case (klines_1sset_va_1,klines_1sset_va_2) of 
                                                           (0 ,  0 ) -> 0
                                                           (0 ,  _ ) -> 0
                                                           (_ ,  0 ) -> 0
                                                           (_ ,  _ ) -> (klines_1sset_va_1 - klines_1sset_va_2)
                     let klines_1sset_va_dr   =      klines_1sset_va_d / klines_1sset_va_2 
                     case (length klines_1ms) of 
                        x|x<8  -> return ((False, AS.DO ),"no")
                        _       -> do 
                                      let sam_span_prh   =     DL.map  AS.knhprice $ DL.take 7 klines_1ms
                                      let sam_span_prl   =     DL.map  AS.knlprice $ DL.take 7 klines_1ms
                                      let sam_span_vol   =     DL.map  AS.knamount $ DL.take 7 klines_1ms
                                      let kline_1m_avg   =     (DL.sum sam_span_vol) / ((fromIntegral $ DL.length sam_span_vol ):: Double)
                                      let kline_1m_max   =     maximum sam_span_prh
                                      let kline_1m_min   =     minimum sam_span_prl 

                                      let kline_1m_fst   =     (!!0) klines_1ms 
                                      let kline_1m_snd   =     (!!1) klines_1ms   
                                      let kline_1s_now   =     (!!0) $ AS.klines_1s kline_1
                                      -------------------------------------------------------
                                      -------------------------------------------------------
                                      --on high point,fst stick is green,snd is red ,ans snd is strong 4times than avg ,then direction is short 
                                      --on low  point,fst stick is red  ,snd is green ,ans snd is strong 4times  than avg,then direction is long 
                                      let volumn_fst_pred   = AS.volumn_pred kline_1m_fst kline_1m_avg
                                      let limithpred_sml    = ((maximum [(AS.knhprice kline_1m_fst),(AS.knhprice kline_1m_snd)]) >=kline_1m_max) 
                                                              -- && (green_or_red_pred kline_1m_fst ==False)
                                                               && volumn_fst_pred
                                                               -- add  not 15m lpoint 
                                      let limitlpred_sml    = ((minimum [(AS.knlprice kline_1m_fst),(AS.knlprice kline_1m_snd)]) <=kline_1m_min) 
                                                              -- && (green_or_red_pred kline_1m_fst ==True)
                                                               && volumn_fst_pred
                                                               -- add  not 15m hpoint 
                                      -------------------------------------------------------
                                      -------------------------------------------------------
                                      --if one stick is hlpoint ,after it is all same direction ,then the first occur other color stick is the reverse direction,fist
                                      --first stick with 2 more same color  stick followed ,and one other color in the latest stick 
                                      let aspan                    =    DL.take 6  klines_1ms 
                                      let (maxvolitem,maxvoindex)  =    get_largest_volumn aspan 
                                      let volumn_snd_pred          =    AS.volumn_pred maxvolitem kline_1m_avg
                                      let sandwichcore_pred        =    same_color_pred  $ DL.take maxvoindex $ DL.tail aspan  
                                      let lastreverse_pred         =    (green_or_red_pred $ last aspan ) /= (green_or_red_pred kline_1m_snd)
                                      let sandwich_pred            =    (maxvoindex<=4) && sandwichcore_pred -- && lastreverse_pred 
                                      let limithpred_big           =    ((maximum $ DL.map AS.knhprice aspan )==kline_1m_max)
                                                                          && (sandwich_pred) 
                                                                          && volumn_snd_pred 

                                      let limitlpred_big           =    ((minimum $ DL.map AS.knlprice aspan )==kline_1m_min) 
                                                                          && (sandwich_pred)  
                                                                          && volumn_snd_pred 

                                      liftIO $ logact logByteStringStdout $ B.pack $ show ("volumn wave---",klines_1sset_va_d
                                                                                                           ,klines_1sset_va_dr
                                                                                                           ,kline_1m_avg
                                                                                                           ,limithpred_sml
                                                                                                           ,limitlpred_sml
                                                                                                           ,limitlpred_big
                                                                                                           ,limithpred_big
                                                                                                           ,volumn_fst_pred
                                                                                                           ,volumn_snd_pred)

                                      case (limithpred_sml,limitlpred_sml,limitlpred_big,limithpred_big) of
                                          (True  ,_     ,_      ,_     ) -> return ((True , AS.DO ),"small") 
                                          (_     ,True  ,_      ,_     ) -> return ((True , AS.UP ),"small") 
                                          (_     ,_     ,True   ,_     ) -> return ((True , AS.UP ),"big"  )
                                          (_     ,_     ,_      ,True  ) -> return ((True , AS.DO ),"big"  )
                                          (_     ,_     ,_      ,_     ) -> return ((False, AS.DO ),"no")
                     -------------------------------------------------------
                     -------------------------------------------------------
    

secondrule :: ((Double,Double),Double) ->  [(Double,Double)]  -> IO ((Int,Trend),String)
secondrule diffpr ablist = do      -- bid is buyer , ask is seller 
                     let ratiol        = DT.map getdiffgridnum ablist
                     let curprsfstdire = snd (ratiol !! 6)
                     let curprmsnddire = snd (ratiol !! 7)
                     let curprsfstdiff = fst (ratiol !! 6)
                     let curprmsnddiff = fst (ratiol !! 7)
                     let cccdata       = ratiol !! 8
                     let ccc           = snd cccdata
                     let badata        = ratiol !! 3
                     let ba            = snd badata
                     let abdata        = ratiol !! 2
                     let ab            = snd badata
                     let ddd           = snd (ratiol !! 9)
                     let eee           = snd (ratiol !! 10)
                     let minpr         = fst $ fst  diffpr
                     let maxpr         = snd $ fst  diffpr
                     let basepr        = snd  diffpr
                     let trend         = case ((curprsfstdire < 0) ,(curprmsnddire < 0)) of
                                               (True ,True )   -> AS.DO
                                               (True ,False)   -> AS.ND 
                                               (False,True )   -> AS.ND
                                               (False,False)   -> AS.UP

                     let ccctrend       = case ccc of 
                                            x|x<(-0.2)   -> (AS.DO,0.001) 
                                            x|x>0.2      -> (AS.UP,0.001) 
                                            _            -> (AS.ND,0) 

                     let (prsti,prsaba)   = case trend of 
                                              AS.DO -> case ba of 
                                                          x|x<0 -> case (fst ccctrend) of 
                                                                      AS.ND  -> (1,"pr")
                                                                      AS.DO  -> (1,"pr1")
                                                                      AS.UP  -> (1,"cc2")
                                                          _     -> case (fst ccctrend) of 
                                                                      AS.ND ->  (1,"no")
                                                                      AS.DO  -> (1,"cc1")
                                                                      AS.UP  -> (1,"cc2")
                                              AS.UP -> case ab of 
                                                          x|x<0 -> case (fst ccctrend) of 
                                                                      AS.ND  -> (1,"pr")
                                                                      AS.UP  -> (1,"pr1")
                                                                      AS.DO  -> (1,"cc2")
                                                          _     -> case (fst ccctrend) of
                                                                      AS.ND ->  (1,"no")
                                                                      AS.UP  -> (1,"cc1")
                                                                      AS.DO  -> (1,"cc2")
                                              _     -> (1,"no")

                     let midquan       = case (basepr < minpr || basepr > maxpr) of 
                                                True  -> 0
                                                False -> (curprsfstdiff + curprmsnddiff)

                     let middquan      = midquan*prsti + (waveonlongsight ccc ddd eee trend) 

                     let finalquan     = case (middquan > 0 ,trend) of 
                                          (True  , AS.DO) -> 0
                                          (False , AS.UP) -> 0
                                          (False , AS.DO) -> middquan
                                          (True  , AS.UP) -> middquan
                                          (_     , _    ) -> 0
                     -- use the three grid (0,0.0002),(0.0002,0.0004),(0.0004,0.0006) to quant the hard degree of trend,also express as boost (add or minus )


                     logact logByteStringStdout $ B.pack $ show ("baratiois--------" ,
                                                                 ( (ablist !!0 )),
                                                                 ( (ablist !!1 )),
                                                                 ( (ablist !!2 )),
                                                                 "aa"++(showdouble  $ snd (ratiol !!1 )),
                                                                 "ab"++(showdouble  $ snd (ratiol !!2 )),
                                                                 "ba"++(showdouble  $ snd (ratiol !!3 )),
                                                                 "aaa"++(showdouble $ snd (ratiol !!6 )),
                                                                 "bbb"++(showdouble $ snd (ratiol !!7 )),
                                                                 "ccc"++(showdouble $ snd (ratiol !!8 )),
                                                                 "ddd"++(showdouble $ snd (ratiol !!9 )),
                                                                 "eee"++(showdouble $ snd (ratiol !!10)),
                                                                 showdouble minpr,
                                                                 showdouble maxpr,
                                                                 showdouble basepr
                                                                 )
                     logact logByteStringStdout $ B.pack $ show (midquan,middquan,finalquan)
                     return ((finalquan,trend),prsaba)



