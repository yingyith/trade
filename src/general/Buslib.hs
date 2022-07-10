{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Buslib( 
      prepopenfun

    ) where

import Control.Applicative
import Control.Lens
import qualified Text.URI as URI
import qualified Data.ByteString  as B
import Data.Maybe (fromJust)
import qualified Data.Map as Map
import Control.Concurrent.STM
import Database.Redis as R
import Control.Concurrent.STM.TVar
import Control.Concurrent.STM.TBQueue
import Control.Monad
import Control.Monad.IO.Class as I 
import qualified Data.Vector as V
import qualified Data.ByteString.Lazy as BLL
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.UTF8 as BL
import qualified Network.HTTP.Base as NTB
import Data.ByteString.Lazy.UTF8 as BLU
import Data.ByteString.Internal (unpackBytes)
import qualified Data.HashMap  as DHM
import Data.Aeson as A
import Data.Aeson.Types as DAT
import Data.Aeson.Lens 
import Data.Text.IO as T
import Data.Text as T
import Data.Map as DM
import Data.Typeable
import GHC.Generics
import Network.HTTP.Req
import Database.Redis
import Data.String.Class as DC
import Data.Digest.Pure.SHA
import Passwd
import System.IO
import Data.Time.Clock.POSIX (getPOSIXTime)
import Globalvar
import Colog (LogAction,logByteStringStdout)
import Logger
import Events
import Order
import Myutils

ab :: ()
ab = ()

prepopenfun :: Double         -> Integer     ->(TVar Curorder)   ->Orderside     -> Double     -> Int  ->   TBQueue Opevent  -> IO () 
prepopenfun stopclosegrid   aresquan       ostvar              curoside        dcp           curtimestampi     tbq     = do
    atomically $ do 
         curorder       <- readTVar ostvar
         let ostate     = orderstate curorder
         let oside      = orderside curorder 
         let ochpostime = chpostime curorder
         case (ostate  == Done ) of 
            True  -> do 
                       let astate      = Prepare
                       let newchpostime  = case ochpostime of 
                                             -1 -> 0
                                             x  -> case oside of 
                                                       curoside   -> x+1 --need return () 
                                                       _          -> 0
                       case (ochpostime==(-1)) of 
                            True -> do 
                                     let aevent = Opevent "prep" aresquan dcp curtimestampi "0" stopclosegrid curoside
                                     addeventtotbqueuestm aevent tbq
                                     let newcurorder = Curorder curoside astate newchpostime
                                     writeTVar ostvar newcurorder
                            False-> do 
                                     case (oside == curoside) of 
                                           True -> do 
                                               let aevent = Opevent "prep" aresquan dcp curtimestampi "0" stopclosegrid curoside
                                               addeventtotbqueuestm aevent tbq
                                               let newcurorder = Curorder curoside astate newchpostime
                                               writeTVar ostvar newcurorder
                                           _    -> return ()

            False -> do 
                       return ()

