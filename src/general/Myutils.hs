{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`
module Myutils (
       outString,
       outArray,
       showdouble
) where

import Database.Redis as R
import Data.Map (Map)
import Data.String
import Data.List as DL
import Data.Maybe 
import Data.Either
import Data.Text as T
import Data.Text.IO as T
import qualified Data.ByteString as B
import qualified Data.ByteString.UTF8 as BL
import qualified Data.ByteString.Lazy as BLL
import Data.Text (Text)
import Network.HTTP.Req
import qualified Data.Map as Map
import Data.Aeson as A
import Data.Aeson.Types as DAT
import Data.Scientific
import Database.Redis
import GHC.Generics
import Data.Monoid ((<>))
import Control.Monad
import Control.Exception
import Control.Monad.Trans (liftIO)
import Data.List.Split as DLT
import Analysistructure as AS
import Globalvar
import Numeric 

outString :: Value -> Text
outString a =  case a of 
                   DAT.String l -> l
                   DAT.Number l -> case floatingOrInteger (l :: Scientific) of 
                                        Right k ->  T.pack $ show k
                                        Left  g ->  T.pack $ showdouble g 
                             --T.pack $ show $ fromRight 0 $ floatingOrInteger  (l::Scientific)

outArray :: Value -> DAT.Array
outArray  a =  case a of 
                   DAT.Array l -> l 

showdouble :: Double -> String
showdouble x = showFFloat (Just 4) x "" 

    
