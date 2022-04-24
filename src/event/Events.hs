{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DataKinds #-}
  module Events (
       Opevent (etype,price,quant,etime,ordid,Opevent),
       addeventtotbqueue
) where

import Control.Concurrent.STM.TBQueue
import Control.Concurrent.STM
import Data.List as DL
import GHC.Generics

data Opevent = Opevent {
                  etype :: String,
                  quant :: Integer,
                  price :: Double,
                  etime :: Int,
                  ordid :: String
}  deriving (Show,Generic) 

addeventtotbqueue :: Opevent -> TBQueue Opevent -> IO ()
addeventtotbqueue evt tbq = do 
   atomically $  do 
                  res <- isFullTBQueue tbq
                  befevt <- tryPeekTBQueue tbq
                  case befevt of 
                     Nothing -> writeTBQueue tbq evt
                     Just l  -> do 
                                  let befevttype = etype l
                                  let befevtmatchpredi  =  (etype l == etype evt) && (DL.any (== befevttype ) ["bopen","sopen"])
                                  let respredi = res && befevtmatchpredi
                                  case respredi of 
                                     False   -> writeTBQueue tbq evt
                                     True    -> return () 
