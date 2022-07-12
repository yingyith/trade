{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`
module Order (
    Ostate (..),
    Orderside (..),
    Curorder (..),
    proordertorediszset,
    procproinitordertorediszset,
    endordertorediszset,
    preorcpreordertorediszset,
    cproordertorediszset,
    ccanordertorediszset,
    acupdtorediszset,
    funcgetorderid,
    funcgetposinf,
    cendordertorediszset,
    settodefredisstate,
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
import Control.Lens
import Control.Exception
import Control.Monad.Trans (liftIO)
import Data.Text  as T
import Httpstructure
import Data.Aeson.Lens
import Data.List.Split as DLT
import Analysistructure as AS
import Numeric
import Globalvar
import Data.Typeable
import Logger
import Lib
import Myutils
import Colog (LogAction,logByteStringStdout)
import Redisutils

data Ostate = Prepare | Process |Proinit | Ppartdone | Pcancel | HalfDone | Cprepare | Cprocess | Cproinit | Cpartdone | Ccancel | Done deriving (Eq,Show)
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

data Orderside = BUY | SELL deriving (Enum,Eq,Show)

data Curorder = Curorder {
      orderside       :: Orderside,
      orderstate      :: Ostate,
      chpostime       :: Int -- change position times
}deriving (Generic,Show)

preorcpreordertorediszset :: Integer -> Orderside -> Double  -> Int -> Double -> Double -> Redis ()
preorcpreordertorediszset sumres oside pr  stamp grid insertstamp = do 
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
   let lastside = recorditem !! 1
   let lastgrid = read (recorditem !! 6) :: Double
   let lastquan = read (recorditem !! 4) :: Integer
   let mergequan = read (recorditem !! 7) :: Integer
   let shmergequan =  show mergequan
   let quanty = toInteger sumres
   liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord++"----preorcpre---------" )

   when (recordstate == (show $ fromEnum Done) )  $ do -- sametime the append pr should have condition of close price
       let side = case oside of 
                        BUY  -> "BUY" 
                        SELL -> "SELL" 
       when (mergequan == 0 && quanty > 0) $ do
           let otype = "Prep" :: String
           let quantity = quanty 
           let orderid =  show stamp 
           let shprice =  show pr
           let shquant =  show quantity
           let shstate =  show $ fromEnum Prepare
           let shgrid = showdouble  grid
           let lmergequan ="0" 
           let abyvaluestr = BL.fromString $  DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
           void $ zadd abykeystr [(-insertstamp,abyvaluestr)]

       when (mergequan == 0 && quanty < 0) $ do
           let otype = "Prep" :: String
           let quantity = abs quanty 
           let orderid =  show stamp 
           let shprice =  show pr
           let shquant =  show quantity
           let shstate =  show $ fromEnum Prepare
           let shgrid = showdouble  grid
           let lmergequan ="0" 
           let abyvaluestr = BL.fromString $  DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
           void $ zadd abykeystr [(-insertstamp,abyvaluestr)]

       when (mergequan /= 0 && quanty > 0) $ do
           let side = case lastside of 
                     "BUY" -> "BUY"
                     "SELL" -> "SELL"
           when (mergequan < 1000) $ do      -- high frq trade
               let otype = "Prep" :: String
               let orderid =  show stamp 
               let shprice =  show pr
               let shquant =  show (2*lastquan) 
               let shstate =  show $ fromEnum Prepare
               let shgrid = showdouble $  getnewgrid mergequan  --add pos = 10
               let lmergequan = show mergequan
               let abyvaluestr = BL.fromString $  DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
               void $ zadd abykeystr [(-insertstamp,abyvaluestr)]
           when (mergequan >= 1000) $  do      -- high frq trade
               let otype = "Prep" :: String
               let orderid =  show stamp 
               let shprice =  show pr
               let shquant =  show lastquan 
               let shstate =  show $ fromEnum Prepare
               let shgrid = showdouble $ getnewgrid mergequan
               let lmergequan = show mergequan
               let abyvaluestr = BL.fromString $  DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
               void $ zadd abykeystr [(-insertstamp,abyvaluestr)]

       when (mergequan /= 0 && quanty < 0) $ do
           let side = case lastside of 
                     "BUY" -> "BUY"
                     "SELL" -> "SELL"
           when (mergequan > -1000) $ do      -- high frq trade
               let otype = "Prep" :: String
               let orderid =  show stamp 
               let shprice =  show pr
               let shquant =  show (2*lastquan) 
               let shstate =  show $ fromEnum Prepare
               let shgrid = showdouble $  getnewgrid mergequan  --add pos = 10
               let lmergequan = show mergequan
               let abyvaluestr = BL.fromString $  DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
               void $ zadd abykeystr [(-insertstamp,abyvaluestr)]
           when (mergequan <= -1000) $  do      -- high frq trade
               let otype = "Prep" :: String
               let orderid =  show stamp 
               let shprice =  show pr
               let shquant =  show lastquan 
               let shstate =  show $ fromEnum Prepare
               let shgrid = showdouble $ getnewgrid mergequan
               let lmergequan = show mergequan
               let abyvaluestr = BL.fromString $  DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
               void $ zadd abykeystr [(-insertstamp,abyvaluestr)]


   when (recordstate == (show $ fromEnum HalfDone)) $ do -- if curpr orderpr  > grid   then append new order,and need merge
       let otype = "Oprep" :: String
       let quantity = lastquan 
       let orderid =  show stamp 
       let side = case lastside of 
                     "BUY" -> "SELL"
                     "SELL" -> "BUY"
       let shprice =  showdouble (lastpr)
       let shquant =  show (quantity)
       let shstate =  show $ fromEnum Cprepare
       let lmergequan = show mergequan
       let shgrid = showdouble lastgrid
       let abyvaluestr = BL.fromString $  DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
       void $ zadd abykeystr [(-insertstamp,abyvaluestr)]
--
proordertorediszset ::  Double -> Double  -> Redis (Integer,(Bool,Double))
proordertorediszset pr stamp  = do 
   -- alter the state 
   --res <- zrange abykeystr 0 1
   --let replydomarray = DLT.splitOn "|" $ BLU.toString cachetime
   let abykeystr = BL.fromString orderkey
   let coin = "ADA" :: String
   let otype = "Open" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let side = recorditem !! 1
   let diffpr = case side of 
                     "BUY" -> 0.004
                     "SELL" -> -0.004
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
                    return (lastquan,(True,pr+diffpr))
       False ->  return (lastquan,(False,pr))

--
procproinitordertorediszset :: Integer -> Double -> String -> Int -> Double -> Redis ()
procproinitordertorediszset quan pr ordid  stampi insertstamp = do 
   let abykeystr = BL.fromString orderkey
   --let side = "BUY" :: String
   let coin = "ADA" :: String
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
   let shquant   =  show quan
   let lastgrid  = read (recorditem !! 6) :: Double
   let mergequan = read (recorditem !! 7) :: Integer
   let lmergequan = show mergequan

   let stamp = fromIntegral stampi :: Double
   let shgrid = showdouble lastgrid

   when (DL.any (== recordstate) [(show $ fromEnum Ccancel),(show $ fromEnum Cprocess)] )  $ do 
       let otype = "CInit" :: String
       let shstate   =  show $ fromEnum Cproinit
       let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
       void $ zadd abykeystr [(-insertstamp,abyvaluestr)]

   when (DL.any (== recordstate) [(show $ fromEnum Pcancel),(show $ fromEnum Process)] )  $ do 
       let otype = "Init" :: String
       let shstate   =  show $ fromEnum Proinit
       let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
       void $ zadd abykeystr [(-insertstamp,abyvaluestr)]

--
pexpandordertorediszset :: Integer -> Double -> Int -> Double -> Orderside -> Redis ()
pexpandordertorediszset quan pr otimestamp insertstamp oside = do 
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
   let coin =  "ADA"
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
   let shgrid = show lastgrid
   --only add but not alter ,if state change ,add a new record,but need to trace the orderid
   when ((DL.any (recordstate ==) [show $ fromEnum Proinit , show $ fromEnum Ppartdone ])==True) $ do
       let shstate = show $ fromEnum Ppartdone  
       let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,lastside,otype,lastorderid,shquant,shprice,shgrid,shmergequan,shstate]
       void $ zadd abykeystr [(-insertstamp,abyvaluestr)]

   when ((DL.any (recordstate ==) [show $ fromEnum Cproinit , show $ fromEnum Cpartdone ])==True) $ do
       let shstate = show $ fromEnum Cpartdone  
       let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,lastside,otype,lastorderid,shquant,shprice,shgrid,shmergequan,shstate]
       void $ zadd abykeystr [(-insertstamp,abyvaluestr)]
--
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
   holdpospr <- getkvfromredis holdprkey
   holdposquan <- getkvfromredis holdposkey

   let recordstate = DL.last recorditem
   let lastgrid = read (recorditem !! 6) :: Double
   let mergequan = read (recorditem !! 7) :: Integer
   let orderid =  lastorderid
   --let shquant =  show quan
   let shquant = show (abs $  read holdposquan :: Int)
   let shgrid  = showdouble lastgrid

   when (DL.any (== recordstate) [(show $ fromEnum Proinit),(show $ fromEnum Ppartdone)] ) $ do
       let shprice = holdpospr 
       let otype = "Hdone" 
       let shstate =  show $ fromEnum HalfDone
       let shmergequan = case side of 
                           "BUY"   -> show mergequan
                           "SELL"  -> show mergequan
       liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord ++ "-----hlfdone--------")
       let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,shmergequan,shstate]
       void $ zadd abykeystr [(-insertstamp,abyvaluestr)]

   when (DL.any (== recordstate) [(show $ fromEnum Cproinit),(show $ fromEnum Cpartdone)] ) $ do
       let shprice = show pr
       let otype = "Done" 
       let shstate =  show $ fromEnum Done
       let shmergequan = show mergequan
       liftIO $ logact logByteStringStdout $ BC.pack $ (lastrecord ++ "-----done--------")
       let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,shmergequan,shstate]
       void $ zadd abykeystr [(-insertstamp,abyvaluestr)]


--
cproordertorediszset :: Double -> Orderside  -> Redis (Integer,(Bool,Double))
cproordertorediszset stamp oside  = do 
   let abykeystr = BL.fromString orderkey
   let coin = "ADA" :: String
   let otype = "Taken" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let lastside = recorditem !! 1
   let side = lastside
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
   let closepr = case oside of 
                        BUY  -> lastpr+lastgrid 
                        SELL -> lastpr-lastgrid
   case (recordstate == (show $ fromEnum Cprepare) ) of 
       True ->  do
                  let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,shmergequan,shstate]
                  void $ zadd abykeystr [(-stamp,abyvaluestr)]
                  return (lastquan,(True,closepr))
       False -> return (0,(False,0))

ccanordertorediszset :: Double -> Redis ()
ccanordertorediszset stamp = do  --set to Ccancel state.In websocket pipe flow, then after weboscket recieve order cancel event,then can merge order/append new pos,then set to halfdone
   let abykeystr = BL.fromString orderkey
   let coin = "ADA" :: String
   let otype = "Cancel" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let lastside = recorditem !! 1
   let side = lastside
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
       False -> return () 


cendordertorediszset :: Integer  -> Int -> Redis ()
cendordertorediszset quan  otimestamp = do 
   let abykeystr = BL.fromString orderkey
   let coin = "ADA" :: String
   let otype = "Done" :: String
   let stamp    = fromIntegral otimestamp  :: Double
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let lastside = recorditem !! 1
   let side = lastside
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

settodefredisstate :: String -> String  -> String -> String -> Double -> Integer -> Double -> Integer -> Double -> Redis ()
settodefredisstate side otype state orderid  pr quan grid  mergequan stamp = do 
   let abykeystr = BL.fromString orderkey
   let coin = "ADA" :: String
   let shgrid = showdouble grid
   let shprice =  showdouble pr
   let shquant =  show quan
   let shstate =  state
   let shmergequan =  show mergequan
   let abyvaluestr = BL.fromString  $ DL.intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,shmergequan,shstate]
   void $ zadd abykeystr [(-stamp,abyvaluestr)]

acupdtorediszset :: Integer -> Double  -> Int -> Redis ()
acupdtorediszset quan pr  usdtbal = do 
   setkvfromredis holdposkey $ show quan
   setkvfromredis holdprkey $ showdouble pr


funcgetorderid :: Value -> IO ()
funcgetorderid avalue = do 
    let aorderidobj  = avalue ^? key "orderId"
    let acorderidobj = avalue ^? key "clientOrderId"
    liftIO $ logact logByteStringStdout $ BC.pack $ show  ("-------cancelorder---------" ,acorderidobj,aorderidobj)
    let aorderid            = T.unpack $ outString $ fromJust aorderidobj 
    let acorderid            = T.unpack $ outString $ fromJust acorderidobj 
    liftIO $ logact logByteStringStdout $ BC.pack $ ("-------cancelorder---------" )
    cancelorder aorderid acorderid
    return ()  

funcgetposinf :: [Value] -> IO (Integer,(Double,String))
funcgetposinf avalues = do 
    let avalue = avalues !! 0 
    let holdposstr = avalue ^? key "positionAmt"
    let possidestr = avalue ^? key "positionSide"
    let holdprstr  = avalue ^? key "entryPrice"
    let holdpos            =  read $ T.unpack $ outString $ fromJust holdposstr :: Integer
    let holdpr            = read $ T.unpack $ outString $ fromJust holdprstr  :: Double
    let poside            = read $ T.unpack $ outString $ fromJust possidestr  :: String
    return (holdpos,(holdpr,poside))
