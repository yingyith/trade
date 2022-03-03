{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
module Sndsrule
    ( 
     sndregionrule
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
import Prelude as DT
import Data.Text.IO as TIO
import Data.ByteString (ByteString)
import Data.Text.Encoding
import System.IO as SI
import Data.Aeson
import Data.Aeson.Lens
import qualified Data.ByteString.Char8 as B
import Data.Aeson.Types
import Analysistructure as AS
import Httpstructure
import Globalvar



sndregionrule :: [Klinedata] -> [Double] -> IO Integer
sndregionrule minpr sheet  = do 
--   let lp = sheet!!0
--   let hp = sheet!!1
--   let lhdiff = hp-lp
--   let interval = fst minpr
--   let pr = snd minpr
--   let action | (pr >= (hp-lhdiff/4)) = (return $ (fromJust $ risksheet!?interval)!!1)
--              | (pr < (hp-lhdiff/4) && pr >= (hp-lhdiff/3)) = (return $ (fromJust $  risksheet!?interval)!!0)
--              | (pr > (lp+lhdiff/4) && pr <= (lp+lhdiff/3)) = (return $ (fromJust $ risksheet!?interval)!!2)
--              | (pr <= (lp+lhdiff/4))  = (return $ (fromJust $  risksheet!?interval)!!3)
--              | (pr > (lp+lhdiff/3) && pr < (hp-lhdiff/3)) = return 15
--   action
    return 0

