{-# LANGUAGE DeriveGeneric #-}
module Lib
    ( 
     getrsi
    ) where
import GHC.Generics
import Data.Aeson
import Data.Text
import Data.List as DL
import Httpstructure
import Control.Monad
import Control.Monad.IO.Class
import Analysistructure

getrsi :: [Hlnode] -> IO (Int,String)
getrsi hl = do 
  liftIO $ print "enter getesi"
  liftIO $ print hl
  let klen = DL.length hl
  liftIO $ print klen
  let updiff   =  [(cprice $ (!!i) al) - (cprice $ (!!(i-1)) al  ) | i <- [1,klen-1] ,let idiff = (cprice $ (!!i) al)-(cprice $ (!!(i-1)) al) in idiff > 0] where al = hl
  let downdiff =  [(cprice $ (!!i) al) - (cprice $ (!!(i-1)) al  ) | i <- [1,klen-1] ,let idiff = (cprice $ (!!i) al)-(cprice $ (!!(i-1)) al) in idiff < 0] where al = hl
  liftIO $ print "enter getesi2"
  liftIO $ print "+++++++++++++"
  liftIO $ print updiff
  liftIO $ print hl
  liftIO $ print "+++++++++++++"
  let gain = sum updiff
  let loss = abs $ sum downdiff
  let rs = gain/loss 
  let rsi  = (100 - 100 /(1+rs))
  return (round rsi,"")
