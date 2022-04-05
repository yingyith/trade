{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`
module Order (
    Ostate (..),
    proordertorediszset,
    hlfendordertorediszset,
    preorcpreordertorediszset,
    cproordertorediszset,
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
import Globalvar
import Data.Typeable

data Ostate = Prepare | Process | HalfDone | Cprepare | Cprocess | Done
instance Enum Ostate where 
     toEnum 0 = Prepare
     toEnum 1 = Process
     toEnum 2 = HalfDone
     toEnum 3 = Cprepare
     toEnum 4 = Cprocess
     toEnum 5 = Done
     fromEnum Prepare = 0
     fromEnum Process = 1
     fromEnum HalfDone = 2
     fromEnum Cprepare = 3
     fromEnum Cprocess = 4
     fromEnum Done = 5

preorcpreordertorediszset :: Int -> Double  -> Integer -> Double -> Redis ()
preorcpreordertorediszset sumres pr  stamp grid = do 
-- quantity ,side ,price ,ostate
   let price  = pr :: Double
   let coin = "ADA" :: String
   let otype = "Open" :: String
   let abykeystr = BL.fromString orderkey
   let stampi = fromIntegral stamp :: Double
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let recordstate = last recorditem
   --liftIO $ print ("++++bef preorcpre record is -------------------------")
   --liftIO $ print (recorditem)
   let lastprr = recorditem !! 5
   --liftIO $ print (lastprr)
   let lastpr = read (recorditem !! 5) :: Double
   let lastgrid = read (recorditem !! 6) :: Double
   let lastquan = read (recorditem !! 4) :: Integer
   let mergequan = read (recorditem !! 7) :: Integer
   let shmergequan =  show mergequan
   when (any (== recordstate) [(show $ fromEnum HalfDone),(show $ fromEnum Cprocess)] && ((recordstate == (show $ fromEnum Cprocess)) && (pr< (lastpr-grid)) ))  $ do -- sametime the append pr should have condition of close price
       --merge two order need add two record,add a field that record last quantity bef merge 
       let quanty = toInteger sumres
       let quantity = case compare quanty 10 of
                           LT -> quanty 
                           GT -> 10 
                           _  -> 100
       let orderid =  show stamp 
       let side = "BUY" :: String
       let shprice =  show pr
       let minquan = (round (10/pr))+2 :: Integer

       let addquant =  case compare quantity minquan of
                           LT -> show minquan
                           _  -> show quantity
       --liftIO $ print (shquant)
       let shquant = show (lastquan*2 )
       let shstate =  show $ fromEnum Prepare
       let lmergequan = show lastquan
       let shgrid = show grid
       when (quantity > 0) $ do
           let abyvaluestr = BL.fromString $  intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
           void $ zadd abykeystr [(-stampi,abyvaluestr)]

   when (recordstate == (show $ fromEnum Done) )  $ do -- sametime the append pr should have condition of close price

       --liftIO $ print ("enter prepare is -------------------------")
       let quanty = toInteger sumres
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
       --liftIO $ print (shquant)
       let shstate =  show $ fromEnum Prepare
       let shgrid = show lastgrid
       let lmergequan ="0" 
       when (quantity > 0) $ do
           let abyvaluestr = BL.fromString $  intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
           void $ zadd abykeystr [(-stampi,abyvaluestr)]

   when (recordstate == (show $ fromEnum HalfDone)) $ do
       let quantity = lastquan 
       let orderid =  show stamp 
       let side = "SELL" :: String
       let shprice =  show (lastpr+0.002)
       let shquant =  show quantity
       let shstate =  show $ fromEnum Cprepare
       let lmergequan = show lastquan
       let shgrid = show lastgrid
       when (quantity > 0) $ do
           let abyvaluestr = BL.fromString $  intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,lmergequan,shstate]
           void $ zadd abykeystr [(-stampi,abyvaluestr)]

proordertorediszset :: Integer -> Double -> Double -> Redis ()
proordertorediszset quan pr stamp = do 
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
   liftIO $ print (pr)
   let recordstate = last recorditem
   let orderid =  show stamp 
   let shprice =  show pr
   let shquant =  show quan
   let shstate =  show $ fromEnum Process
   let lastgrid = read (recorditem !! 6) :: Double
   let mergequan = read (recorditem !! 7) :: Integer
   --let lastquan = read (recorditem !! 4) :: Integer
   let lmergequan = show mergequan
   let shgrid = show lastgrid
   --only add but not alter ,if state change ,add a new record,but need to trace the orderid
   when (recordstate == (show $ fromEnum Prepare) ) $ do
       let abyvaluestr = BL.fromString  $ intercalate "|" [coin,side,otype,lastorderid,shquant,shprice,shgrid,lmergequan,shstate]
       void $ zadd abykeystr [(-stamp,abyvaluestr)]

pexpandordertorediszset :: String -> Integer -> Double -> Double -> Redis ()
pexpandordertorediszset side quan pr stamp = do 
   -- this operation only append the order detail ,not alter the state
   let abykeystr = BL.fromString orderkey
   let coin = case side of 
                   "BUY" -> "ADA"
                   "SELL" -> "USDT"
   let otype = "Taken" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   liftIO $ print ("expand record is -------------------------")
   liftIO $ print (recorditem)
   let lastorderid = recorditem !! 3
   let lastorderquant = read $ recorditem !!4 ::Integer
   let lastordertype = recorditem !!2 
   let lastgrid = read (recorditem !! 6) :: Double
   let recordstate = last recorditem
   let orderid =  show stamp 
   let shprice =  show pr
   let shquant =  case lastordertype of 
                    "Open"-> show quan
                    "Taken"-> show (quan+ lastorderquant)
   let mergequan = read (recorditem !! 7) :: Integer
   let shmergequan =  show mergequan
   liftIO $ print (side ++ "is -------------------------------")
   let shstate = case side of 
                      "BUY" -> show $ fromEnum Process
                      "SELL" -> show $ fromEnum Cprocess
   let prestate = show $ fromEnum Prepare
   let cprestate = show $ fromEnum Cprepare
   let tpred = (any (recordstate ==) [prestate, cprestate ,shstate])
   let abyvaluestr = [coin,side,otype,lastorderid,shquant,shprice,shstate]
   let abyvaluestr = intercalate "|" [coin,side,otype,lastorderid,shquant,shprice,shstate]
   let abyvaluestr = BL.fromString  $ intercalate "|" [coin,side,otype,lastorderid,shquant,shprice,shstate]
   let shgrid = show lastgrid
   --only add but not alter ,if state change ,add a new record,but need to trace the orderid
   when (tpred == True) $ do
       liftIO $ print ("bef pexpand add  is -------------------------")
       let abyvaluestr = BL.fromString  $ intercalate "|" [coin,side,otype,lastorderid,shquant,shprice,shgrid,shmergequan,shstate]
       liftIO $ print (abyvaluestr)
       liftIO $ print ("bef pexpand add  is -------------------------")
       liftIO $ print (abyvaluestr)
       void $ zadd abykeystr [(-stamp,abyvaluestr)]
       liftIO $ print ("aft pexpand add  is -------------------------")

hlfendordertorediszset :: Integer  -> Double -> Redis ()
hlfendordertorediszset quan  stamp  = do 
   let abykeystr = BL.fromString orderkey
   let side = "BUY" :: String
   let coin = "ADA" :: String
   let otype = "Hdone" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let pr = recorditem !! 5
   --liftIO $ print ("bef haldend record is -------------------------")
   --liftIO $ print (recorditem)
   --liftIO $ print (pr)
   let recordstate = last recorditem
   let lastgrid = read (recorditem !! 6) :: Double
   let mergequan = read (recorditem !! 7) :: Integer
   let shmergequan =  show mergequan
   let orderid =  lastorderid
   let shprice =  pr
   let shquant =  show quan
   let shstate =  show $ fromEnum HalfDone
   let shgrid  = show lastgrid
   when (recordstate == (show $ fromEnum Process) ) $ do
       let abyvaluestr = BL.fromString  $ intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,shmergequan,shstate]
       void $ zadd abykeystr [(-stamp,abyvaluestr)]


--cpreordertorediszset :: Integer -> Double -> Redis ()
--cpreordertorediszset quan  stamp  = do 
--   let abykeystr = BL.fromString orderkey
--   let side = "SELL" :: String
--   let coin = "ADA" :: String
--   let otype = "Open" :: String
--   res <- zrange abykeystr 0 0
--   let tdata = case res of 
--                    Right c -> c
--   let lastrecord = BL.toString $ tdata !!0
--   let recorditem = DLT.splitOn "|" lastrecord
--   let lastorderid = recorditem !! 3
--   liftIO $ print ("bef cpre record is -------------------------")
--   liftIO $ print (recorditem)
--   let recordstate = last recorditem
--   let lastpr = recorditem !! 4
--   let orderid =  show lastorderid ::String
--   let shprice =  show lastpr
--   let shquant =  show quan
--   let shstate =  show $ fromEnum Cprepare
--   when (recordstate == (show $ fromEnum HalfDone) ) $ do
--       let abyvaluestr = BL.fromString  $ intercalate "|" [coin,side,otype,orderid,shquant,shprice,shstate]
--       void $ zadd abykeystr [(-stamp,abyvaluestr)]

cproordertorediszset :: Integer -> Double -> Double -> Redis ()
cproordertorediszset quan pr stamp  = do 
   let abykeystr = BL.fromString orderkey
   let side = "SELL" :: String
   let coin = "ADA" :: String
   let otype = "Taken" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   --liftIO $ print ("bef cpro record is -------------------------")
   --liftIO $ print (recorditem)
   let lastorderid = recorditem !! 3
   let lastgrid = read (recorditem !! 6) :: Double
   let recordstate = last recorditem
   let orderid =  show lastorderid ::String
   let shprice =  show pr
   let shquant =  show quan
   let shstate =  show $ fromEnum Cprocess
   let mergequan = read (recorditem !! 7) :: Integer
   let shmergequan =  show mergequan
   let shgrid = show lastgrid
   when (recordstate == (show $ fromEnum Cprepare) ) $ do
       let abyvaluestr = BL.fromString  $ intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,shmergequan,shstate]
       void $ zadd abykeystr [(-stamp,abyvaluestr)]

cendordertorediszset :: Integer  -> Double -> Redis ()
cendordertorediszset quan  stamp = do 
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
   let recordstate = last recorditem
   let orderid =  show lastorderid ::String
   let lastgrid = read (recorditem !! 6) :: Double
   let shgrid = show lastgrid
   let shprice =  show pr
   let shquant =  show quan
   let shstate =  show $ fromEnum Done
   let mergequan = read (recorditem !! 7) :: Integer
   let shmergequan =  show mergequan
   when (recordstate == (show $ fromEnum Cprocess) ) $ do
       let abyvaluestr = BL.fromString  $ intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,shmergequan,shstate]
       void $ zadd abykeystr [(-stamp,abyvaluestr)]

ctestendordertorediszset :: Integer->Double  -> Double -> Redis ()
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
   let recordstate = last recorditem
   let lastgrid = read (recorditem !! 6) :: Double
   let shgrid = show lastgrid
   let orderid =  show lastorderid ::String
   let shprice =  show pr
   let shquant =  show quan
   let shstate =  show $ fromEnum Done
   let mergequan = read (recorditem !! 7) :: Integer
   let shmergequan =  show mergequan
   when (recordstate == (show $ fromEnum Cprepare) ) $ do
       let abyvaluestr = BL.fromString  $ intercalate "|" [coin,side,otype,orderid,shquant,shprice,shgrid,shmergequan,shstate]
       void $ zadd abykeystr [(-stamp,abyvaluestr)]
