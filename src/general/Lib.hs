{-# LANGUAGE DeriveGeneric #-}
module Lib
    ( 
     getrsi
    ) where
import GHC.Generics
import Data.Aeson
import Data.Text
import Data.List as DL
import Prelude as DT
import Httpstructure
import Control.Monad
import Control.Monad.IO.Class
import Analysistructure

getrsi :: [Hlnode] -> IO (Int,String)
getrsi hl = do 
  let klen = 8
  let updiff   =  [(cprice $ (!!i) hl) -(cprice $ (!!(i+1)) hl)   | i <- [0,klen-2] ] 
  let downdiff =  [(cprice $ (!!i) hl) -(cprice $ (!!(i+1)) hl)   | i <- [0,klen-2] ] 

  let gain = case (DL.length updiff) of 
                  x|x<1 -> 0.00001 
                  _     -> (abs $ sum updiff)
  let loss = case (DL.length downdiff) of 
                  x|x<1 -> 0.00001
                  _     -> (abs $ sum downdiff)
  liftIO $ print (updiff,downdiff)
  liftIO $ print (gain,loss)
  let rs = gain/loss 
  let rsi  = (100 - (100 /(1+rs)))
  return (round rsi,"")
