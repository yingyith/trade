{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DataKinds #-}
  module Events (
       Opevent (etype,price,quant,etime,ordid,oside,eprofit,Opevent),
       Cronevent (ectype,eccont,Cronevent),
       addoeventtotbqueuestm,
       addeventtotbqueue,
       addeventtotbqueuestm,
       addoeventtotbqueue
) where

import Control.Concurrent.STM.TBQueue
import Control.Concurrent.STM
import Control.Exception 
import qualified Data.ByteString.UTF8 as BL
import qualified Data.ByteString.Char8 as B
import Colog (LogAction,logByteStringStdout)
import Data.List as DL
import GHC.Generics
import Logger
import Order

data Opevent = Opevent {
                  etype   :: String,
                  quant   :: Integer,
                  price   :: Double,
                  etime   :: Int,
                  ordid   :: String,
                  eprofit :: Double,
                  oside   :: Orderside
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
                                  let befevtmatchpredi  =  (etype l == etype evt) && (DL.any (== befevttype ) ["bopen","sopen","scancel"])
                                  let respredi = res && befevtmatchpredi
                                  case respredi of 
                                     False   -> writeTBQueue tbq evt
                                     True    -> return () 
   `catch` (\(e :: SomeException) -> do
        logact logByteStringStdout $ B.pack $ show ("order ",e,evt)
     )

addeventtotbqueuestm :: Opevent -> TBQueue Opevent -> STM ()
addeventtotbqueuestm evt tbq = do 
   res <- isFullTBQueue tbq
   befevt <- tryPeekTBQueue tbq
   case befevt of 
      Nothing -> writeTBQueue tbq evt
      --Nothing -> return ()
      Just l  -> do 
                   let befevttype = etype l
                   let befevtmatchpredi  =  (etype l == etype evt) && (DL.any (== befevttype ) ["bopen","sopen","scancel"])
                   let respredi = res && befevtmatchpredi
                   case respredi of 
                      False   -> writeTBQueue tbq evt
                     -- False   -> return () 
                      True    -> return () 


data Cronevent = Cronevent {
                  ectype :: String,
                  eccont :: BL.ByteString      
}  deriving (Show,Generic) 

addoeventtotbqueue :: Cronevent -> TBQueue Cronevent -> IO ()
addoeventtotbqueue evt tbq = do 
   atomically $  do 
                  res <- isFullTBQueue tbq
                  befevt <- tryPeekTBQueue tbq
                  case befevt of 
                     Nothing -> writeTBQueue tbq evt
                     Just l  -> case res of 
                                   False -> writeTBQueue tbq evt
                                   True  -> return ()
   `catch` (\(e :: SomeException) -> do
        logact logByteStringStdout $ B.pack $ show ("oforwardevent",e)
     )

addoeventtotbqueuestm :: Cronevent -> TBQueue Cronevent -> STM ()
addoeventtotbqueuestm evt tbq = do 
                                    res <- isFullTBQueue tbq
                                    befevt <- tryPeekTBQueue tbq
                                    case befevt of 
                                       Nothing -> writeTBQueue tbq evt
                                       Just l  -> case res of 
                                                     False -> writeTBQueue tbq evt
                                                     True  -> return ()

