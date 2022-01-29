{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
module Strategy
    ( 
      
      
      
      
    ) where
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`

import Data.Monoid ((<>))
import Control.Monad
import Control.Exception
import Control.Monad.Trans (liftIO)
import Control.Concurrent
import Network.WebSockets (ClientApp, receiveData, sendClose, sendTextData)
import Network.WebSockets.Connection as NC
import Control.Concurrent.Async
import Data.Text as T
import Data.Text.IO as T
import Data.ByteString (ByteString)
import Data.Text.Encoding
import System.IO as SI
import Data.Aeson
import Data.Aeson.Lens
import qualified Data.ByteString.Char8 as B
import Data.Aeson.Types
import Analysistucture 

class  Emptystrategy  where
  opencondition :: Nprice->position->Oprice>(Bool,position,oprice)
  closecondition :: Nprice->(Bool,position,cprice)

  --check currenenv situation
data positionenv = positionenv {
  positionnum :: Int,
  positiontype :: String, --(0,open long,1 open short,2,close long ,3 close short)
  positionoprice :: Float -- position open price 
 } 

type currentenv = currentenv currentprice  positionenv  

  
---define a  function ,that is if price down is too much like from 1.67 fall down to 0.7 ,so if price fall,then risk para is smaller.Accroding to risk para,make the position weight.



