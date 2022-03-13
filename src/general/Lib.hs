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
  let klen = 8
  let updiff   =  [(cprice $ (!!i) al) - (cprice $ (!!(i-1)) al  ) | i <- [1,klen-1] ,let idiff = (cprice $ (!!i) al)-(cprice $ (!!(i-1)) al) in idiff > 0] where al = hl
  let downdiff =  [(cprice $ (!!i) al) - (cprice $ (!!(i-1)) al  ) | i <- [1,klen-1] ,let idiff = (cprice $ (!!i) al)-(cprice $ (!!(i-1)) al) in idiff < 0] where al = hl

  let gain = case (DL.length updiff) of 
                  x|x<1 -> 0.001 
                  _     -> (abs $ sum updiff)/(fromIntegral $ DL.length updiff :: Double) 
  let loss = case (DL.length downdiff) of 
                  x|x<1 -> 0.001
                  _     -> (abs $ sum downdiff)/(fromIntegral $ DL.length downdiff :: Double)
  let rs = gain/loss 
  let rsi  = (100 - (100 /(1+rs)))
  return (round rsi,"")
