{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Analysistructure
    ( 
      Hlnode (..),
    ) where
import Control.Applicative
import qualified Text.URI as URI
import qualified Data.ByteString  as B
import Data.Maybe (fromJust)
import qualified Data.Map as Map
import Control.Monad
import Control.Monad.IO.Class as I 
import qualified Data.Vector as V
import qualified Data.ByteString.Lazy.Internal as BLI
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.UTF8 as BL
import Data.Aeson as A
import Data.Aeson.Types as AT
import Data.Text (Text)
import Data.Typeable
import GHC.Generics
import Network.HTTP.Req
import Database.Redis
import Data.String.Class as DC

--data HLtree  = Leaf {
--               index :: Integer,
--               price :: Double,
--               rank :: Integer,
--               stype :: String }
--               | Branch HLtree HLtree deriving Show 

data Hlnode = Hlnode {
              hprice :: Double,
              lprice :: Double,
              rank :: Integer,
              stype :: String, -- high or low` 
              rtype :: String  -- '5min' or '1h'
              } deriving (Show,Generic)

               
