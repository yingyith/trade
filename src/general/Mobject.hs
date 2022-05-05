{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Mobject 
    ( 
      initupddepth
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
import Myutils
import Analysistructure
import Httpstructure


initupddepth :: R.Connection -> IO Depthset 
initupddepth conn = do 
    qrydepthh     <- querydepth
    let qrydepth  =  getlistfrdep $ fromJust qrydepthh
    let qrybids   =  DHM.fromList $ fst $ snd qrydepth 
    let qryasks   =  DHM.fromList $ snd $ snd qrydepth
    let lastu     =  fst qrydepth
    let depthdata =  Depthset lastu  0  0   DHM.empty   qrybids qryasks 
   -- let bidso = fst $ snd $ getlistfrdep   qrydepth 
   -- let askso = snd $ snd $ getlistfrdep   qrydepth 
   -- let bidsoo =  outArray bidso  
   -- let asksoo =  outArray askso 
   -- let bidslist = DV.map depthitemtoredis bidsoo
   -- let askslisr = DV.map depthitemtoredis asksoo
   -- runRedis conn $ do 
   --          depthtoredis bidso "bids"
   --          depthtoredis askso "asks"

    return depthdata

