{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`
module Order (
    Ostate,
    proordertorediszset,
    endordertorediszset,
    preordertorediszset

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

data Ostate = Prepare | Process | End 
instance Enum Ostate where 
     toEnum 0 = Prepare
     toEnum 1 = Process
     toEnum 2 = End
     fromEnum Prepare = 0
     fromEnum Process = 1
     fromEnum End = 2

preordertorediszset :: Integer -> Double -> Integer -> Redis ()
preordertorediszset quan pr stamp  = do 
-- quantity ,side ,price ,ostate
   let quantity = quan :: Integer
   let price  = pr :: Double
   let side = "Buy" :: String
   let coin = "ADA" :: String
   let otype = "Open" :: String
   let ostate = Prepare 
   let abykeystr = BL.fromString orderkey
   let stampi = fromIntegral stamp :: Double
   res <- zrange abykeystr 0 0
   liftIO $ print ("order history!")
   liftIO $ print (res)
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let recordstate = last recorditem
   let orderid = stamp
   --liftIO $ print (recordstate)
   when (recordstate == "2" && quan > 0) $ do
       let abyvaluestr = BL.fromString  $ intercalate "|" [coin,side,show otype,show orderid,show quantity,show price,show $ fromEnum Prepare]
       void $ zadd abykeystr [(-stampi,abyvaluestr)]

proordertorediszset :: Integer -> Double -> Double -> Redis ()
proordertorediszset quan pr stamp = do 
   -- alter the state 
   --res <- zrange abykeystr 0 1
   --let replydomarray = DLT.splitOn "|" $ BLU.toString cachetime
   let abykeystr = BL.fromString orderkey
   let side = "Buy" :: String
   let coin = "ADA" :: String
   let otype = "Open" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let recordstate = last recorditem
   let quan = recorditem !! 4
   let pr = recorditem !! 5
   liftIO $ print ("good time to http ack")
   --only add but not alter ,if state change ,add a new record,but need to trace the orderid
   when (recordstate == "0" ) $ do
       let abyvaluestr = BL.fromString  $ intercalate "|" [coin,side,show otype,show lastorderid,show quan,show pr,show $ fromEnum Process]
       void $ zadd abykeystr [(-stamp,abyvaluestr)]

endordertorediszset :: Integer -> Double -> Redis ()
endordertorediszset quan pr   = do 
   let abykeystr = BL.fromString orderkey
   let side = "Buy" :: String
   let coin = "ADA" :: String
   let otype = "Open" :: String
   res <- zrange abykeystr 0 0
   let tdata = case res of 
                    Right c -> c
   let lastrecord = BL.toString $ tdata !!0
   let recorditem = DLT.splitOn "|" lastrecord
   let lastorderid = recorditem !! 3
   let recordstate = last recorditem
   return ()
