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

getrsi :: [Klinedata] -> IO Double
getrsi hl = do 
  let klen = DL.length hl
  let updiff   =  [(read $ kclose $ (!!i) al :: Double)-(read $ kclose $ (!!(i-1)) al ::Double ) | i <- [1,klen-1] ,let idiff = (read $ kclose $ (!!i) al :: Double)-(read $ kclose $ (!!(i-1)) al ::Double ) in idiff > 0] where al = hl
  let downdiff =  [(read $ kclose $ (!!i) al :: Double)-(read $ kclose $ (!!(i-1)) al ::Double ) | i <- [1,klen-1] ,let idiff = (read $ kclose $ (!!i) al :: Double)-(read $ kclose $ (!!(i-1)) al ::Double ) in idiff < 0] where al = hl
  let gain = sum updiff
  let loss = abs $ sum downdiff
  let rs = gain/loss 
  let rsi  = (100 - 100 /(1+rs))
  return rsi
