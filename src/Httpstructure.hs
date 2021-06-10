{-# LANGUAGE OverloadedStrings #-}
module Httpstructure
    ( WebsocketRsp,
      DataSet,
      KDataSet
    ) where
import Control.Applicative
import Data.Aeson
import Data.Text (Text)

data WebsocketRsp = WebsocketRsp
    {
      streams :: Text 
    , datas  :: DataSet
    } deriving Show

data DataSet = DataSet
    {
      e :: Text
    , e1 :: Text
    , s :: Text
    , kdata  :: KDataSet
    } deriving Show

data KDataSet = KDataSet{
      t :: Int
    , t1 :: Int
    , s1 :: Text
    , i :: Text
    , f :: Int
    , l1 :: Int
    , o :: Text
    , c :: Text
    , h :: Text
    , l :: Text
    , v1 :: Text
    , n :: Int
    , x :: Bool
    , q :: Text
    , v :: Text
    , q1 :: Text
    , b1 :: Text
    } deriving Show


instance FromJSON WebsocketRsp where
  parseJSON (Object w) = 
     WebsocketRsp <$> w .: "streams"
                  <*> w .: "data"

instance FromJSON DataSet where
  parseJSON (Object v) = 
     DataSet <$> v .: "e"
             <*> v .: "E"
             <*> v .: "s"
             <*> v .: "data"
  parseJSON _ = empty

instance FromJSON KDataSet where
  parseJSON (Object k) = 
     KDataSet <$> k .: "t"
              <*> k .: "T"
              <*> k .: "s"
              <*> k .: "i"
              <*> k .: "f"
              <*> k .: "L"
              <*> k .: "o"
              <*> k .: "c"
              <*> k .: "h"
              <*> k .: "l"
              <*> k .: "v"
              <*> k .: "n"
              <*> k .: "x"
              <*> k .: "q"
              <*> k .: "v"
              <*> k .: "Q"
              <*> k .: "B"
  parseJSON _ = empty 
