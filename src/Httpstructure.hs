{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Httpstructure
    ( 
      parsekline,
      Mseries,
      Stick,
      HStick (op,cp,lp,hp,st),
      DpairMserie,
      sticks,
      getmsilist,
      pinghandledo,
      getintervalfrpair,
      getmsfrpair,
      Klinedata (ktype,kname,kopen,kclose,khigh,klow,ktime),
    ) where
import Control.Applicative
import qualified Text.URI as URI
import qualified Data.ByteString  as B
import Data.Maybe (fromJust)
import qualified Data.Map as Map
import Control.Monad
import Control.Monad.IO.Class as I 
import qualified Data.Vector as V
import qualified Data.ByteString.Lazy.Internal as BLI
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.UTF8 as BL
import Data.Aeson as A
import Data.Aeson.Types as AT
import Data.Text (Text)
import Data.Typeable
import GHC.Generics
import Network.HTTP.Req
import Database.Redis
import Data.String.Class as DC


    

parsekline :: String -> IO (DpairMserie) 
--getStickToCache :: String -> IO () 
parsekline nstr  = runReq defaultHttpConfig $ do
    let ouri = https "api.binance.com" /: "api" /: "v3" /: "klines"  
    let intervals=["5m","15m","1h","4h","12h"]
    let symbol = "ADAUSD"
    let tnstr = nstr 
    let limit = 3
    let params = 
          "symbol" =: ("ADAUSDT" :: Text) <>
          "interval" =: (tnstr ) <>
          "limit" =: (15 :: Int)
    areq <- req GET ouri NoReqBody lbsResponse params
    let breq = responseBody areq
    --liftIO $ print (areq)
    --liftIO $ DC.putStrLn (breq)
    --convert areq to sticks
    --convert sticks to redis cache wl
    let creq =  (A.decode breq) :: Maybe Mseries
    --decode bytestring to haskell object
    --liftIO $ print (responseBody areq :: Value)
    let dreq = DpairMserie nstr creq 
    return dreq

--  "[[1633089300000,\"2.23000000\",\"2.23700000\",\"2.23000000\",\"2.23700000\",\"723388.10000000\",1633089599999,\"1616255.57940000\",1772,\"365047.10000000\",\"815571.73890000\",\"0\"],[1633089600000,\"2.23600000\",\"2.24600000\",\"2.23400000\",\"2.24100000\",\"1273906.90000000\",1633089899999,\"2853730.42640000\",4737,\"821288.20000000\",\"1840100.60630000\",\"0\"],[1633089900000,\"2.24100000\",\"2.24200000\",\"2.24000000\",\"2.24100000\",\"10992.10000000\",1633090199999,\"24635.62260000\",66,\"10407.60000000\",\"23325.88350000\",\"0\"]]"

--data Stick = Stick {
--      stime :: Integer,
--      oprice :: String,
--      cprice :: String,
--      hprice :: String,
--      lprice :: String,
--      samount :: String
--} deriving Generic

pinghandledo :: Maybe BL.ByteString -> IO ()
pinghandledo a  =  runReq defaultHttpConfig $ do
    let ae = case a of
               Just a -> a
    let aa = BL.toString ae 
    let ouri = https "api.binance.com" /: "api" /: "v3" /: "userDataStream"  
    let params = "listenKey" =: (aa :: String) 
    areq <- req PUT ouri NoReqBody lbsResponse params
    liftIO $ print (areq)

data HStick = HStick {
      st :: Integer,
      op :: String,
      cp :: String,
      hp :: String,
      lp :: String
} deriving (Show,Generic)


data Mseries = Mseries  [HStick] deriving (Show,Generic) 

type MInterval = String
data DpairMserie = DpairMserie MInterval (Maybe Mseries) deriving (Show,Generic) 

getmsfrpair :: DpairMserie -> Maybe Mseries
getmsfrpair (DpairMserie a b) = b 

getintervalfrpair :: DpairMserie -> String
getintervalfrpair (DpairMserie a b) = a

getmsilist :: Mseries -> [HStick]
getmsilist (Mseries t ) = t
getmsilist (Mseries _ ) = []
--instance  Show Mseries 


instance FromJSON HStick where
   parseJSON (Array v) = do
          st <- parseJSON $ v V.! 0
          op <- parseJSON $ v V.! 1
          hp <- parseJSON $ v V.! 2
          lp <- parseJSON $ v V.! 3
          cp <- parseJSON $ v V.! 4
          return $ HStick st op hp lp cp
   parseJSON _ = mzero

--mapOdds :: (a -> a) -> [a] -> [a]
--   mapOdds f al = case al! 

instance FromJSON Mseries where
   parseJSON (Array v) = do
     ptsList <- mapM parseJSON $ V.toList v
     return $ Mseries ptsList
   parseJSON _ = mzero

data Stick = Stick Text deriving Show

sticks :: Map.Map String [a]
sticks = Map.fromList [("1min",[]),("5min",[]),("15min",[]),("60min",[]),("4hour",[]),("12hour",[]),("3day",[]),("1week",[])]

instance FromJSON Stick where 
    parseJSON json = do
            Array arr <- pure json
            Just (Array arr0) <- pure (arr V.!? 0) 
            Just (A.String stxt) <- pure (arr0 V.!? 0)
            pure (Stick stxt)
    parseJSON _ = mzero

--"{\"stream\":\"ethusdt@kline_1m\",\"data\":{\"e\":\"kline\",\"E\":1639083854455,\"s\":\"ETHUSDT\",\"k\":{\"t\":1639083840000,\"T\":1639083899999,\"s\":\"ETHUSDT\",\"i\":\"1m\",\"f\":702680151,\"L\":702680405,\"o\":\"4111.56000000\",\"c\":\"4111.41000000\",\"h\":\"4112.71000000\",\"l\":\"4110.00000000\",\"v\":\"117.02120000\",\"n\":255,\"x\":false,\"q\":\"481113.77283200\",\"V\":\"22.34560000\",\"Q\":\"91870.06074800\",\"B\":\"0\"}}}"

data Klinedata = Klinedata {
         ktype :: String,
         kname :: String, --""
         kopen :: String,
         kclose :: String,
         khigh :: String,
         klow :: String,
         ktime :: Integer
} deriving Show

--data Stickwebsocketdata = Stickwebsocketdata {
--         sname :: String,  --"kline"
--         spair :: String, -- "ETHISDT"
--         sdata :: !AT.Object 
--} deriving Show
--
--data Websocketdata = Websocketdata {
--         coinpair :: String,
--         stickwebsocketdata :: !AT.Object
--} deriving Show

instance FromJSON Klinedata where 
  parseJSON (Object o) = 
    Klinedata <$> (pure "kline")
              <*> ((o .: "data") >>= (.: "k") >>= (.: "s"))
              <*> ((o .: "data") >>= (.: "k") >>= (.: "o"))
              <*> ((o .: "data") >>= (.: "k") >>= (.: "c"))
              <*> ((o .: "data") >>= (.: "k") >>= (.: "h"))
              <*> ((o .: "data") >>= (.: "k") >>= (.: "l"))
              <*> ((o .: "data") >>= (.: "k") >>= (.: "t"))
  parseJSON _ = mzero

--instance FromJSON Websocketdata where 
--  parseJSON (Object o) = 
--    Websocketdata <$> (o .: "e")
--                  <*> (o .: "s")
--                  <*> (o .: "k")
--  parseJSON _ = mzero
--
--instance FromJSON Stickwebsocketdata where 
--  parseJSON (Object o) = 
--    Stickwebsocketdata <$> (o .: "stream")
--                       <*> (o .: "data")
--  parseJSON _ = mzero
-----------------------------
