{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`
module Order (
    Ostate (..),
    proordertorediszset,
    procproinitordertorediszset,
    cproinitordertorediszset,
    endordertorediszset,
    preorcpreordertorediszset,
    cproordertorediszset,
    ccanordertorediszset,
    pcanordertorediszset,
    acupdtorediszset,
    cendordertorediszset,
    ctestendordertorediszset,
    pexpandordertorediszset
) where

import Database.Redis as R
import Data.Map (Map)
import Data.String
import Data.List as DL
import Data.Maybe 
import qualified Data.ByteString as B
import Data.ByteString.Char8 as  BC
import qualified Data.ByteString.UTF8 as BL
import qualified Data.ByteString.Lazy as BLL
import Data.Text (Text)
import Network.HTTP.Req
import qualified Data.Map as Map
import Data.Aeson as A
import Data.Aeson.Types
import Database.Redis
import GHC.Generics
import Data.Monoid ((<>))
import Control.Monad
import Control.Exception
import Control.Monad.Trans (liftIO)
import Httpstructure
import Data.List.Split as DLT
import Analysistructure as AS
import Numeric
import Globalvar
import Data.Typeable
import Logger
import Myutils
import Colog (LogAction,logByteStringStdout)
import Redisutils

data Ostate = Prepare | Process |Proinit | Ppartdone | Pcancel | HalfDone | Cprepare | Cprocess | Cproinit | Cpartdone | Ccancel | Done
instance Enum Ostate where 
     toEnum 0   = Prepare
     toEnum 1   = Process
     toEnum 2   = Proinit  --take order and init successful with order id 
     toEnum 3   = Ppartdone  --take order and init successful with order id 
     toEnum 4   = Pcancel   
     toEnum 5   = HalfDone -- order totoally finish
     toEnum 6   = Cprepare
     toEnum 7   = Cprocess
     toEnum 8   = Cproinit --take order and init successful with order id
     toEnum 9   = Cpartdone  --take order and init successful with order id 
     toEnum 10  = Ccancel   
     toEnum 11  = Done      -- order totoally finish 
     fromEnum Prepare     = 0
     fromEnum Process     = 1
     fromEnum Proinit     = 2
     fromEnum Ppartdone   = 3
     fromEnum Pcancel     = 4
     fromEnum HalfDone    = 5
     fromEnum Cprepare    = 6
     fromEnum Cprocess    = 7
     fromEnum Cproinit    = 8
     fromEnum Cpartdone   = 9
     fromEnum Ccancel     = 10   -- need to merge 
     fromEnum Done        = 11

preorcpreordertorediszset :: Int -> Double  -> Integer -> Double -> Double -> Redis ()
preorcpreordertorediszset sumres pr  stamp grid insertstamp = do 
-- quantity ,side ,price ,ostate
   let price  = pr :: Double
   let coin = "ADA" :: String
   let abykeystr = BL.fromString orderkey
   let stampi = fromIntegral stamp :: Double
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let recordstate = DL.last recorditem
   --liftIO $ print ("++++bef preorcpre record is -------------------------")
   --liftIO $ print (recorditem)
   let lastprr = recorditem !! 5
   let lastorderid = recorditem !! 3
   --liftIO $ print (lastprr)
   let lastpr = read (recorditem !! 5) :: Double
   let lastgrid = read (recorditem !! 6) :: Double
   let lastquan = read (recorditem !! 4) :: Integer
   let mergequan = read (recorditem !! 7) :: Integer
   let shmergequan =  show mergequan
   let quanty = toInteger sumres
   liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord++"----preorcpre---------" )
   when (DL.any (== recordstate) [(show $ fromEnum Ccancel) ] )  $ do 
       --append new order after cancel
       let otype = "Reset" :: String
       let quantity = case compare quanty 10 of
                           LT -> quanty 
                           GT -> 10 
                           _  -> 100
       let orderid =  lastorderid 
       let side = "BUY" :: String
       let shprice =  showdouble lastpr
       let minquan = (round (10/pr))+2 :: Integer

       let addquant =  case compare quantity minquan of
                           LT -> show minquan
                           _  -> show quantity
       --liftIO $ print (shquant)
       let shgrid = showdouble grid
       let lmergequan = show (lastquan+mergequan)

       when (pr<= (lastpr-grid)) $ do  
           let shstate =  show $ fromEnum Done
           let shquant = show (lastquan ) --new quan should equel to old quan ,then can double
           let shprice = showdouble pr
           let mergebefquan = show (lastquan)  --totlolly quan  = shquant + mergebefquan
           --need more strict condition ,and double the quant`
           let abyvaluestr = BL.fromString $  DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,mergebefquan,shstate]
           void $ zadd abykeystr [(-insertstamp,abyvaluestr)]

     --  when (pr>= (lastpr-grid)) $ do
     --      let shstate =  show $ fromEnum HalfDone
     --      let lmergequan = show mergequan
     --      let shquant = show (lastquan )
     --      let shprice = lastprr
     --      let abyvaluestr = BL.fromString $  DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
     --      void $ zadd abykeystr [(-insertstamp,abyvaluestr)]

   when (recordstate == (show $ fromEnum Done) )  $ do -- sametime the append pr should have condition of close price

       when (mergequan == 0 && quanty > 0) $ do
           let otype = "Prep" :: String
           let quantity = case compare quanty 10 of
                               LT -> quanty 
                               GT -> 10 
                               _  -> 10
           let orderid =  show stamp 
           let side = "BUY" :: String
           let shprice =  show pr
           let minquan = (round (10/pr))+2 :: Integer

           let shquant =  case compare quantity minquan of
                               LT -> show minquan
                               _  -> show quantity
           let shstate =  show $ fromEnum Prepare
           let shgrid = showdouble  grid
           let lmergequan ="0" 
           let abyvaluestr = BL.fromString $  DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
           void $ zadd abykeystr [(-insertstamp,abyvaluestr)]

       when (mergequan /= 0 && quanty > 0) $ do
           let otype = "Prep" :: String
           let orderid =  show stamp 
           let side = "BUY" :: String
           let shprice =  show pr
           let shquant =  show lastquan 
           let shstate =  show $ fromEnum Prepare
           let shgrid = showdouble  grid
           let lmergequan = show mergequan
           let abyvaluestr = BL.fromString $  DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
           void $ zadd abykeystr [(-insertstamp,abyvaluestr)]


   when (recordstate == (show $ fromEnum HalfDone)) $ do -- if curpr orderpr  > grid   then append new order,and need merge
       let otype = "Oprep" :: String
       let quantity = lastquan 
       let orderid =  show stamp 
       let side = "SELL" :: String
       let shprice =  showdouble (lastpr)
       let shquant =  show (quantity+mergequan)
       let shstate =  show $ fromEnum Cprepare
       let lmergequan = show 0
       let shgrid = showdouble  grid
       when (quantity > 0) $ do
           let abyvaluestr = BL.fromString $  DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
           void $ zadd abykeystr [(-insertstamp,abyvaluestr)]

proordertorediszset ::  Double -> Double  -> Redis (Integer,(Bool,Double))
proordertorediszset pr stamp  = do 
   -- alter the state 
   --res <- zrange abykeystr 0 1
   --let replydomarray = DLT.splitOn "|" $ BLU.toString cachetime
   let abykeystr = BL.fromString orderkey
   let side = "BUY" :: String
   let coin = "ADA" :: String
   let otype = "Open" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   --liftIO $ print ("bef process record is -------------------------")
   let recordstate = DL.last recorditem
   let lastquan = read (recorditem !! 4) :: Integer
   let orderid =  show stamp 
   let shprice =  showdouble pr
   let shquant =  show lastquan
   let shstate =  show $ fromEnum Process
   let lastgrid = read (recorditem !! 6) :: Double
   let mergequan = read (recorditem !! 7) :: Integer
   --let lastquan = read (recorditem !! 4) :: Integer
   let lmergequan = show mergequan
   let shgrid = show lastgrid
   liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord ++ "---------preorder---------")
   --only add but not alter ,if state change ,add a new record,but need to trace the orderid
   case  (recordstate == (show $ fromEnum Prepare) ) of 
       True  ->  do
                    let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,lastorderid,shquant,shprice,shgrid,lmergequan,shstate]
                    void $ zadd abykeystr [(-stamp,abyvaluestr)]
                    return (lastquan,(True,pr+0.003))
       False ->  return (lastquan,(False,pr))

pcanordertorediszset :: Double -> Redis (Integer,Bool)
pcanordertorediszset stamp = do  --set to Ccancel state.In websocket pipe flow, then after weboscket recieve order cancel event,then can merge order/append new pos,then set to halfdone
   let abykeystr = BL.fromString orderkey
   let side = "BUY" :: String
   let coin = "ADA" :: String
   let otype = "Cancel" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let recordstate = DL.last recorditem
   let orderid =  lastorderid 
   let shstate =  show $ fromEnum Ccancel
   let lastgrid = read (recorditem !! 6) :: Double
   let shprice = recorditem !! 5
   let shquant = recorditem !! 4
   let mergequan = read (recorditem !! 7) :: Integer
   let lmergequan = show mergequan
   let shgrid = show lastgrid
   liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord ++ "---------pcancel---------")
   case (DL.any (== recordstate) [(show $ fromEnum Ppartdone),(show $ fromEnum Proinit)] ) of 
       True  ->  do 
                    let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,lastorderid,shquant,shprice,shgrid,lmergequan,shstate]
                    void $ zadd abykeystr [(-stamp,abyvaluestr)]
                    return (0,True)
       False -> return (0,False)

procproinitordertorediszset :: Integer -> Double -> String -> Int -> Double -> Redis ()
procproinitordertorediszset quan pr ordid  stampi insertstamp = do 
   let abykeystr = BL.fromString orderkey
   --let side = "BUY" :: String
   let coin = "ADA" :: String
   let otype = "Init" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let lastside = recorditem !! 1
   let side = lastside
   let recordstate = DL.last recorditem
   let lastquan  = read (recorditem !! 4) :: Integer
   let orderid   =  ordid 
   let shprice   =  showdouble pr
   let shquant   =  case side of 
                       "BUY"  -> show quan
                       "SELL" -> show lastquan 
   let shstate   =  case side of 
                        "BUY" -> show $ fromEnum Proinit
                        "SELL" -> show $ fromEnum Cproinit
   let lastgrid  = read (recorditem !! 6) :: Double
   let mergequan = read (recorditem !! 7) :: Integer
   let lmergequan = show mergequan
   let stamp = fromIntegral stampi :: Double
   let shgrid = show lastgrid
   when (DL.any (== recordstate) [(show $ fromEnum Cprocess),(show $ fromEnum Process)] )  $ do 
       let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
       void $ zadd abykeystr [(-insertstamp,abyvaluestr)]


pexpandordertorediszset :: Integer -> Double -> Int -> Double -> Redis ()
pexpandordertorediszset quan pr otimestamp insertstamp = do 
   -- this operation only append the order detail ,not alter the state
   let abykeystr = BL.fromString orderkey
   let otype = "Merge" :: String
   let stamp    = fromIntegral otimestamp  :: Double
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   --liftIO $ print ("expand record is -------------------------")
   --liftIO $ print (recorditem)
   let lastorderid = recorditem !! 3
   let lastside = recorditem !! 1
   let coin = case lastside of 
                   "BUY" -> "ADA"
                   "SELL" -> "USDT"
   let lastorderquant = read $ recorditem !!4 ::Integer
   let lastordertype = recorditem !!2 
   let lastgrid = read (recorditem !! 6) :: Double
   let recordstate = DL.last recorditem
   let orderid =  show stamp 
   let shprice =  show pr
   let shquant =  show quan
   let mergequan = read (recorditem !! 7) :: Integer
   let shmergequan =  show mergequan
   liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord ++ "--------------pexpandorder--------------")
   let shstate = case lastside of 
                      "BUY" -> show $ fromEnum Ppartdone
                      "SELL" -> show $ fromEnum Cpartdone
   let prestate = show $ fromEnum Proinit
   let cprestate = show $ fromEnum Cproinit
   let tpred = (DL.any (recordstate ==) [prestate, cprestate ,shstate])
   let shgrid = show lastgrid
   --only add but not alter ,if state change ,add a new record,but need to trace the orderid
   when (tpred == True) $ do
       liftIO $ print ("bef pexpand add  is -------------------------")
       let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,lastside,otype,lastorderid,shquant,shprice,shgrid,shmergequan,shstate]
       liftIO $ print (abyvaluestr)
       liftIO $ print ("bef pexpand add  is -------------------------")
       liftIO $ print (abyvaluestr)
       void $ zadd abykeystr [(-insertstamp,abyvaluestr)]
       liftIO $ print ("aft pexpand add  is -------------------------")

endordertorediszset :: Integer ->Double -> Int -> Double -> Redis ()
endordertorediszset quan pr otimestamp insertstamp = do 
   let abykeystr = BL.fromString orderkey
   let coin = "ADA" :: String
   let stamp    = fromIntegral otimestamp  :: Double
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let lastside = recorditem !! 1
   let side = lastside
   let otype =  case side of 
                    "BUY" -> "Hdone" 
                    "SELL" -> "Done"
   holdpospr <- getkvfromredis holdprkey
   let recordstate = DL.last recorditem
   let lastgrid = read (recorditem !! 6) :: Double
   let mergequan = read (recorditem !! 7) :: Integer
   let shmergequan =  show mergequan
   let orderid =  lastorderid
   let shquant =  show quan
   let shstate =  case side of 
                    "BUY" -> show $ fromEnum HalfDone
                    "SELL" -> show $ fromEnum Done
   let shgrid  = showdouble lastgrid

   when (DL.any (== recordstate) [(show $ fromEnum Proinit),(show $ fromEnum Ppartdone)] ) $ do
       let shprice = holdpospr 
       liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord ++ "-----hlfdone--------")
       let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,shmergequan,shstate]
       void $ zadd abykeystr [(-insertstamp,abyvaluestr)]

   when (DL.any (== recordstate) [(show $ fromEnum Cproinit),(show $ fromEnum Cpartdone)] ) $ do
       let shprice = show pr
       liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord ++ "-----done--------")
       let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,shmergequan,shstate]
       void $ zadd abykeystr [(-insertstamp,abyvaluestr)]



cproordertorediszset :: Double  -> Redis (Integer,(Bool,Double))
cproordertorediszset stamp  = do 
   let abykeystr = BL.fromString orderkey
   let side = "SELL" :: String
   let coin = "ADA" :: String
   let otype = "Taken" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let lastgrid = read (recorditem !! 6) :: Double
   let lastquan = read (recorditem !! 4) :: Integer
   let lastpr = read (recorditem !! 5) :: Double
   let recordstate = DL.last recorditem
   let orderid =  lastorderid 
   let shprice =  show lastpr
   let shquant =  show lastquan
   let shstate =  show $ fromEnum Cprocess
   let mergequan = read (recorditem !! 7) :: Integer
   let shmergequan =  show mergequan
   let shgrid = show lastgrid
   liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord++"-------cpro---------")
   case (recordstate == (show $ fromEnum Cprepare) ) of 
       True ->  do
                  let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,shmergequan,shstate]
                  void $ zadd abykeystr [(-stamp,abyvaluestr)]
                  return (lastquan,(True,lastpr+lastgrid))
       False -> return (0,(False,0))

ccanordertorediszset :: Double -> Redis (Integer,Bool)
ccanordertorediszset stamp = do  --set to Ccancel state.In websocket pipe flow, then after weboscket recieve order cancel event,then can merge order/append new pos,then set to halfdone
   let abykeystr = BL.fromString orderkey
   let side = "SELL" :: String
   let coin = "ADA" :: String
   let otype = "Cancel" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let recordstate = DL.last recorditem
   let orderid =  lastorderid 
   let shstate =  show $ fromEnum Ccancel
   let lastgrid = read (recorditem !! 6) :: Double
   let shprice = recorditem !! 5
   let shquant = recorditem !! 4
   let mergequan = read (recorditem !! 7) :: Integer
   let lmergequan = show mergequan
   let shgrid = show lastgrid
   liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord ++ "---------cancel---------")
   case (DL.any (== recordstate) [(show $ fromEnum Cprocess),(show $ fromEnum Cpartdone),(show $ fromEnum Cproinit)] ) of 
       True  ->  do 
                     let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,lastorderid,shquant,shprice,shgrid,lmergequan,shstate]
                     void $ zadd abykeystr [(-stamp,abyvaluestr)]
                     return (0,True)
       False -> return (0,False) 

cproinitordertorediszset :: Integer -> Double -> Int -> Redis ()
cproinitordertorediszset quan pr stampi = do 
   let abykeystr = BL.fromString orderkey
   let side = "SELL" :: String
   let coin = "ADA" :: String
   let otype = "init" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let recordstate = DL.last recorditem
   let lastquan  = read (recorditem !! 4) :: Integer
   let orderid   =  show stampi 
   let shprice   =  showdouble pr
   let shquant   =  show quan
   let shstate   =  show $ fromEnum Cproinit
   let lastgrid  = read (recorditem !! 6) :: Double
   let mergequan = read (recorditem !! 7) :: Integer
   let lmergequan = show mergequan
   let stamp = fromIntegral stampi :: Double
   let shgrid = show lastgrid
   liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord ++ "---------cproinitorder---------")
   when (recordstate == (show $ fromEnum Process) ) $ do
       let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,lastorderid,shquant,shprice,shgrid,lmergequan,shstate]
       void $ zadd abykeystr [(-stamp,abyvaluestr)]

cendordertorediszset :: Integer  -> Int -> Redis ()
cendordertorediszset quan  otimestamp = do 
   let abykeystr = BL.fromString orderkey
   let side = "SELL" :: String
   let coin = "ADA" :: String
   let otype = "Done" :: String
   let stamp    = fromIntegral otimestamp  :: Double
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let pr = recorditem !! 5
   let recordstate = DL.last recorditem
   let orderid =  lastorderid
   let lastgrid = read (recorditem !! 6) :: Double
   let shgrid = show lastgrid
   let shprice =  show pr
   let shquant =  show quan
   let shstate =  show $ fromEnum Done
   let mergequan = read (recorditem !! 7) :: Integer
   let shmergequan =  show mergequan
   liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord++ "-------cend---------" )
   when (recordstate == (show $ fromEnum Cprocess) ) $ do
       let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,shmergequan,shstate]
       void $ zadd abykeystr [(-stamp,abyvaluestr)]

ctestendordertorediszset :: Integer-> Double  -> Double -> Redis ()
ctestendordertorediszset quan pr  stamp = do 
   let abykeystr = BL.fromString orderkey
   let side = "SELL" :: String
   let coin = "ADA" :: String
   let otype = "Done" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   --liftIO $ print ("bef end record is -------------------------")
   --liftIO $ print (recorditem)
   let lastorderid = recorditem !! 3
   let pr = recorditem !! 5
   let recordstate = DL.last recorditem
   let lastgrid = read (recorditem !! 6) :: Double
   let shgrid = show lastgrid
   let orderid =  show lastorderid ::String
   let shprice =  show pr
   let shquant =  show quan
   let shstate =  show $ fromEnum Done
   let mergequan = read (recorditem !! 7) :: Integer
   let shmergequan =  show mergequan
   liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord )
   when (recordstate == (show $ fromEnum Cprepare) ) $ do
       let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,shmergequan,shstate]
       void $ zadd abykeystr [(-stamp,abyvaluestr)]

acupdtorediszset :: Integer -> Double  -> Int -> Redis ()
acupdtorediszset quan pr  usdtbal = do 
   setkvfromredis holdposkey $ show quan
   setkvfromredis holdprkey $ showdouble pr
