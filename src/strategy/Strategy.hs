{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
module Strategy
    ( 
     saferegionrule
    ) where
import Data.Monoid ((<>))
import Control.Monad
import Control.Exception
import Control.Monad.Trans (liftIO)
import Control.Concurrent
import Network.WebSockets (ClientApp, receiveData, sendClose, sendTextData)
import Network.WebSockets.Connection as NC
import Control.Concurrent.Async
import Data.Text as T
import Data.Map 
import Data.Maybe
import Data.Text.IO as T
import Data.ByteString (ByteString)
import Data.Text.Encoding
import System.IO as SI
import Data.Aeson
import Data.Aeson.Lens
import qualified Data.ByteString.Char8 as B
import Data.Aeson.Types


--every grid have a position value, 1min value -> 15  up_fast->5      oppsite -> -15 fall_fast -> -25
--                                  5min value -> 20  up_fast->5     oppsite -> -10 fall_fast -> -20
--                                  15min value -> 15 up_fast->5      oppsite -> -10 fall_fast -> -20
--                                  1hour value -> 10 up_fast->5      oppsite -> -15 fall_fast -> -10
--                                  4hour value -> 30 up_fast->-10     oppsite -> -40 fall_fast -> -60
--                                  1day value -> 5   up_fast->-5      oppsite -> -5  fall_fast -> 0
--                                  3day value -> 5   up_fast->-5      oppsite -> -5  fall_fast -> 0
--                                  only sum of all predication > = 0 ,then can open
risksheet :: Map String [Integer]
risksheet = fromList [
             ("1m", [20,-10,10,-25]),
             ("5m", [20,-5,-10,-25]),
             ("15m",[25,-35,-10,-15]),   --15min highpoint  , up_fast must be minus -25 or smaller
             ("1h", [20,10,-10,-25]),
             ("4h", [25,10,-15,-25]),
             ("12h", [5,5,0,0]),
             ("3d", [0,5,0,0])
            ]


saferegionrule :: (String,Double) -> [Double] -> IO Integer
saferegionrule minpr sheet  = do 
   let lp = sheet!!0
   let hp = sheet!!1
   let lhdiff = hp-lp
   let interval = fst minpr
   let pr = snd minpr
   let action | (pr >= (hp-lhdiff/4)) = (return $ (fromJust $ risksheet!?interval)!!1)
              | (pr < (hp-lhdiff/4) && pr >= (hp-lhdiff/3)) = (return $ (fromJust $  risksheet!?interval)!!0)
              | (pr > (lp+lhdiff/4) && pr <= (lp+lhdiff/3)) = (return $ (fromJust $ risksheet!?interval)!!2)
              | (pr <= (lp+lhdiff/4))  = (return $ (fromJust $  risksheet!?interval)!!3)
              | (pr > (lp+lhdiff/3) && pr < (hp-lhdiff/3)) = return 15
   action
   --check  ,if >  highpoint - 1/4 diff , oppsite (risk)
   --check  ,if >  highpoint - 1/3 diff , oppsite (risk)
   --check  ,if <  lowpoint + 1/3 diff  ,oppsite (risk)  
   --check  ,if <  lowpoint + 1/5 diff  ,oppsite (risk)  
   --check 1/3 ,if >  lowpoint + 1/3 diff and  < highpoint-1/3 , positive (risk)

   
