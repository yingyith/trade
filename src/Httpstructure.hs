{-# LANGUAGE OverloadedStrings #-}
module Httpstructure
    ( WebsocketRsp,
      DataSet,
      KDataSet,
      getStickToCache,
      getSticksToCache
    ) where
import Control.Applicative
import qualified Text.URI as URI
import Data.Maybe (fromJust)
import Control.Monad.IO.Class
import Data.Aeson
import Data.Text (Text)
import Network.HTTP.Req
import Rediscache 
import Database.Redis


getSticksToCache :: IO ()
getSticksToCache = do 
    tt <- mapM getStickToCache ["5m","15m","1h","4h"] 
    conn <- connect defaultConnectInfo
    initdict tt conn
    

getStickToCache :: String -> IO (JsonResponse Value) 
--getStickToCache :: String -> IO () 
getStickToCache nstr  = runReq defaultHttpConfig $ do
    let ouri = https "api.binance.com" /: "api" /: "v3" /: "klines"  
    let intervals=["5m","15m","1h","4h","12h"]
    let symbol = "ADAUSDT"
    let tnstr = nstr 
    let limit = 3
    let params = 
          "symbol" =: ("ADAUSDT" :: Text) <>
          "interval" =: (tnstr ) <>
          "limit" =: (3 :: Int)
    areq <- req GET ouri NoReqBody jsonResponse params
    --convert areq to sticks
    --convert sticks to redis cache wl
    liftIO $ print (responseBody areq :: Value)
    return areq

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
