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

getrsi :: [Hlnode] -> Int -> IO (Int,String)
getrsi hl hllen = do 
  let klen = hllen
  let updiff   =  [(cprice $ (!!i) hl) -(cprice $ (!!(i+1)) hl)   | i <- [0..klen-2], (cprice $ (!!i) hl) -(cprice $ (!!(i+1)) hl) > 0] 
  let downdiff =  [(cprice $ (!!i) hl) -(cprice $ (!!(i+1)) hl)   | i <- [0..klen-2], (cprice $ (!!i) hl) -(cprice $ (!!(i+1)) hl) < 0] 

  let gain = case (DL.length updiff) of 
                  x|x<1 -> 0.00001 
                  _     -> (abs $ sum updiff)
  let loss = case (DL.length downdiff) of 
                  x|x<1 -> 0.00001
                  _     -> (abs $ sum downdiff)
  --liftIO $ print (updiff,downdiff,gain,loss)
  let rs = gain/loss 
  liftIO $ print (rs)
  let rsi  = (100 - (100 /(1+rs)))
  return (round rsi,"")
