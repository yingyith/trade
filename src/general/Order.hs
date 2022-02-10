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

data Ostate = Prepare | Process | End 
instance Enum Ostate where 
     toEnum 0 = Prepare
     toEnum 1 = Process
     toEnum 2 = End
     fromEnum Prepare = 0
     fromEnum Process = 1
     fromEnum End = 2

preordertorediszset :: Integer -> Double -> Double -> Redis ()
preordertorediszset quan pr stamp  = do 
-- quantity ,side ,price ,ostate
   let quantity = 10 :: Integer
   let price  = 1.1 :: Double
   let side = "Buy" :: String
   let coin = "ADA" :: String
   let ostate = Prepare 
   let abykeystr = BL.fromString "Order"
   --curtimestampl <- (round . (* 1000) <$> getPOSIXTime )
   --let curtimestamp = curtimestampl :: Integer
   --if last record state is not end ,pass the all process
   res <- zrange abykeystr 0 1
   liftIO $ print (res)
   --
   when (1==1) $ do
       let abyvaluestr = BL.fromString  $ intercalate "|" [coin,side,show quantity,show price,show $ fromEnum Prepare]
       void $ zadd abykeystr [(-stamp,abyvaluestr)]

proordertorediszset :: Integer -> Double -> Redis ()
proordertorediszset quan pr  = do 
   -- alter the state 
   --res <- zrange abykeystr 0 1
   --let replydomarray = DLT.splitOn "|" $ BLU.toString cachetime
   liftIO $ print ("good time to http ack")
   return ()

endordertorediszset :: Integer -> Double -> Redis ()
endordertorediszset quan pr   = do 
--get state of 
   return ()
