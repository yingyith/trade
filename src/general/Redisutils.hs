{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`
module Redisutils (
    getkvfromredis,
    setkvfromredis
) where

import Data.String
import Data.List as DL
import qualified Data.ByteString as B
import Data.ByteString.Char8 as  BC
import qualified Data.ByteString.UTF8 as BL
import qualified Data.ByteString.Lazy as BLL
import qualified Data.ByteString.Lazy.UTF8 as BLU
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Time.LocalTime
import Data.Time.Format
import Data.Text (Text)
import Data.Either
import Data.Maybe
import qualified Data.Map as Map
import Data.Aeson as A
import Data.Aeson.Types
import Database.Redis
import GHC.Generics
import Data.Monoid ((<>))
import Control.Monad
import Control.Exception
import Control.Monad.Trans (liftIO)
import Data.List.Split as DLT
import Globalvar
import Logger
import System.Log.Logger 
import System.Log.Handler (setFormatter)
import System.Log.Handler.Syslog
import System.Log.Handler.Simple
import System.Log.Formatter
import Colog (LogAction,logByteStringStdout)
import Data.Time.Format.ISO8601
import Data.Time.Clock.POSIX


setkvfromredis :: String -> String -> Redis ()
setkvfromredis key value = do 
   let keybs = BL.fromString key
   let valuebs = BL.fromString value
   void $ set keybs valuebs

getkvfromredis :: String -> Redis (String)
getkvfromredis key = do 
   let keybs = BL.fromString key
   valuewithright <- get keybs
   let valueres = case valuewithright of 
                      Right v ->  v
   let value = fromJust valueres 
   return $ BL.toString value
      

