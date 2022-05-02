{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module Httpstructure
    ( 
      parsekline,
      Mseries,
      Depseries,
      Stick,
      takeorder,
      cancelorder,
      HStick (op,cp,lp,hp,st),
      --Wdepseries (depu,depU,deppu,asksh,bidsh),
      Wdepseries (tdata),
      DpairMserie,
      sticks,
      getmsilist,
      getlistfrdep,
      queryorder,
      querypos,
      querydepth,
      queryforder,
      pinghandledo,
      getintervalfrpair,
      getspotbalance,
      getmsfrpair,
      Klinedata (ktype,kname,kopen,kclose,khigh,klow,ktime),
      getcurtimestamp,
      getsectimestamp,
      WSevent (wsdata,wstream)
    ) where
import Control.Applicative
import Control.Lens
import qualified Text.URI as URI
import qualified Data.ByteString  as B
import Data.Maybe (fromJust)
import qualified Data.Map as Map
import Control.Monad
import Control.Monad.IO.Class as I 
import qualified Data.Vector as V
import qualified Data.ByteString.Lazy as BLL
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.UTF8 as BL
import qualified Network.HTTP.Base as NTB
import Data.ByteString.Lazy.UTF8 as BLU
import Data.ByteString.Internal (unpackBytes)
import Data.Aeson as A
import Data.Aeson.Types as DAT
import Data.Aeson.Lens 
import Data.Text.IO as T
import Data.Text as T
import Data.Map as DM
import Data.Typeable
import GHC.Generics
import Network.HTTP.Req
import Database.Redis
import Data.String.Class as DC
import Data.Digest.Pure.SHA
import Passwd
import System.IO
import Data.Time.Clock.POSIX (getPOSIXTime)
import Globalvar
import Colog (LogAction,logByteStringStdout)
import Logger
import Myutils

getorderitem :: IO ()
getorderitem = runReq defaultHttpConfig $ do
    let ouri = https "api.binance.com" /: "api" /: "v3" /: "order"  
    let limit = 3
    let params = 
          "symbol" =: ("ADAUSDT" :: Text)
    areq <- req GET ouri NoReqBody lbsResponse params
    return ()
    
getcurtimestamp :: IO Integer
getcurtimestamp = do
   curtimestamp <- round . (* 1000) <$> getPOSIXTime
   return curtimestamp

getsectimestamp :: IO Integer
getsectimestamp = do
   curtimestamp <- round  <$> getPOSIXTime
   return curtimestamp

getspotbalance :: IO (Double,Double)
getspotbalance = do 
   curtimestamp <- getcurtimestamp
   --liftIO $ print (curtimestamp)
   runReq defaultHttpConfig $ do 
      let astring = BLU.fromString $ ("timestamp="++ (show curtimestamp))
      let signature = BLU.fromString sk
      let ares = showDigest(hmacSha256 signature astring)
      --let ares = showDigest(hmacSha256 signature params)
      --let ouri = "https://fapi.binance.com/fapi/v2/balance"  
      let ouri = "https://fapi.binance.com/fapi/v2/account"  
      --let ouri = "https://api.binance.com/api/v3/account"  
      let auri=ouri<>(T.pack "?signature=")<>(T.pack ares)
      uri <- URI.mkURI auri 
      let passwdtxt = BC.pack Passwd.passwd
      let params = 
            (header "X-MBX-APIKEY" passwdtxt ) <>
            ("timestamp" =: (curtimestamp :: Integer ))<>
            ("signature" =: (T.pack ares :: Text ))
      --liftIO $ print uri
      --liftIO $ print (useHttpsURI uri)

      let (url, options) = fromJust (useHttpsURI uri)
      let areq = req GET url NoReqBody jsonResponse  params
      response <- areq
      let result = responseBody response :: Value
      let adabal = (result ^.. key "assets" .values.filtered (has (key "asset"._String.only "ADA"))) !!0
      let adaadabal = fromJust $ adabal ^? key "availableBalance"
      let aadabal = case adaadabal of 
                          DAT.String l -> l
      let adaball = read $ T.unpack aadabal :: Double
      let usdtbal = (result ^.. key "assets" .values.filtered (has (key "asset"._String.only "USDT"))) !!0
      let usdtusdtbal = fromJust $ usdtbal ^? key "availableBalance"
      let uusdtbal = case usdtusdtbal of 
                          DAT.String l -> l
      let usdtball = read $ T.unpack uusdtbal :: Double
      --let usdtbal = usdtbal ^? key "free"
      --let ares = fromJust $  parseMaybe (.: "signature") result :: String
  --
      --liftIO $ print ("[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]")
      return (adaball,usdtball)

queryorder :: IO ([Value],[Value])
queryorder = do
   let symbol = "ADAUSDT"
   let symboll = "ADAUSDT"
   curtimestamp <- getcurtimestamp
   runReq defaultHttpConfig $ do 
      let signature = BLU.fromString sk
      let passwdtxt = BC.pack Passwd.passwd

      let abody = BLU.fromString $ NTB.urlEncodeVars [("symbol",symbol),("timestamp",show curtimestamp)  ] 
      let ares = showDigest(hmacSha256 signature abody)
      let httpparams = 
            (header "X-MBX-APIKEY" passwdtxt ) <>
            ("symbol" =: (symboll :: Text)) <>
            ("timestamp" =: (curtimestamp :: Integer )) <>
            ("signature" =: (T.pack ares :: Text ))
      let ouri = "https://fapi.binance.com/fapi/v1/openOrders"  
      let auri=ouri<>(T.pack "?signature=")<>(T.pack ares)
      uri <- URI.mkURI auri 
      let (url, options) = fromJust (useHttpsURI uri)
      let areq = req GET url NoReqBody jsonResponse  httpparams
      response  <- areq
      let result = responseBody response :: Value
      let borders = (result^..values.filtered (has (key "side"._String.only "BUY"))) 
      let sorders = (result^..values.filtered (has (key "side"._String.only "SELL"))) 
      liftIO $ logact logByteStringStdout $ BC.pack  $ show ("queryorder ----",borders,"+++++",sorders)
      return (borders,sorders)

querypos :: IO ([Value])
querypos = do
   let symbol = "ADAUSDT"
   let symboll = "ADAUSDT"
   curtimestamp <- getcurtimestamp
   runReq defaultHttpConfig $ do 
      let signature = BLU.fromString sk
      let passwdtxt = BC.pack Passwd.passwd

      let abody = BLU.fromString $ NTB.urlEncodeVars [("symbol",symbol),("timestamp",show curtimestamp)  ] 
      let ares = showDigest(hmacSha256 signature abody)
      let httpparams = 
            (header "X-MBX-APIKEY" passwdtxt ) <>
            ("symbol" =: (symboll :: Text)) <>
            ("timestamp" =: (curtimestamp :: Integer )) <>
            ("signature" =: (T.pack ares :: Text ))
      let ouri = "https://fapi.binance.com/fapi/v2/positionRisk"  
      let auri=ouri<>(T.pack "?signature=")<>(T.pack ares)
      uri <- URI.mkURI auri 
      let (url, options) = fromJust (useHttpsURI uri)
      let areq = req GET url NoReqBody jsonResponse  httpparams
      response  <- areq
      let result = responseBody response :: Value
      let borders = (result^..values.filtered (has (key "symbol"._String.only "ADAUSDT"))) 
      liftIO $ logact logByteStringStdout $ BC.pack  $ show ("querypos ----",borders,"+++++")
      return borders

queryforder :: IO ()
queryforder = do
   let symbol = "ADAUSDT"
   let symboll = "ADAUSDT"
   curtimestamp <- getcurtimestamp
   runReq defaultHttpConfig $ do 
      let signature = BLU.fromString sk
      let passwdtxt = BC.pack Passwd.passwd

      let abody = BLU.fromString $ NTB.urlEncodeVars [("symbol",symbol),("limit","5"),("timestamp",show curtimestamp)  ] 
      let ares = showDigest(hmacSha256 signature abody)
      let httpparams = 
            (header "X-MBX-APIKEY" passwdtxt ) <>
            ("symbol" =: (symboll :: Text)) <>
            ("limit" =: (5 :: Integer )) <>
            ("timestamp" =: (curtimestamp :: Integer )) <>
            ("signature" =: (T.pack ares :: Text ))
      let ouri = "https://fapi.binance.com/fapi/v1/allOrders"  
      let auri=ouri<>(T.pack "?signature=")<>(T.pack ares)
      uri <- URI.mkURI auri 
      let (url, options) = fromJust (useHttpsURI uri)
      let areq = req GET url NoReqBody jsonResponse  httpparams
      response  <- areq
      let result = responseBody response :: Value
      let borders = (result^..values.filtered (has (key "side"._String.only "BUY"))) 
      let sorders = (result^..values.filtered (has (key "side"._String.only "SELL"))) 
      liftIO $ logact logByteStringStdout $ BC.pack  $ show ("queryorder ----",borders,"+++++",sorders)
      return ()

--querydepth :: IO ((Maybe Value,Maybe Value))
querydepth :: IO (Maybe Depseries)
querydepth = do
   let symbol = "ADAUSDT"
   let symboll = "ADAUSDT"
   curtimestamp <- getcurtimestamp
   runReq defaultHttpConfig $ do 
      let signature = BLU.fromString sk
      let passwdtxt = BC.pack Passwd.passwd

      let abody = BLU.fromString $ NTB.urlEncodeVars [("symbol",symbol),("limit","1000"),("timestamp",show curtimestamp)  ] 
      let ares = showDigest(hmacSha256 signature abody)
      let httpparams = 
            (header "X-MBX-APIKEY" passwdtxt ) <>
            ("symbol" =: (symboll :: Text)) <>
            ("limit" =: (1000 :: Integer )) <>
            ("timestamp" =: (curtimestamp :: Integer )) <>
            ("signature" =: (T.pack ares :: Text ))
      let ouri = "https://fapi.binance.com/fapi/v1/depth"  
      let auri=ouri<>(T.pack "?signature=")<>(T.pack ares)
      uri <- URI.mkURI auri 
      let (url, options) = fromJust (useHttpsURI uri)
      areq <- req GET url NoReqBody lbsResponse httpparams
      let result = responseBody areq
      --let sorders = (result ._Object )
      --let sorders = (result ^..(!? 0))
      let ressheet =  (A.decode result) :: Maybe Depseries
     -- let asks =  (A.decode result) :: Maybe Depseries
      --let dreq = DpairMserie nstr creq 
      liftIO $ logact logByteStringStdout $ BC.pack  $ show ("queryorder ----",result)
      return ressheet

cancelorder :: String -> IO ()
cancelorder orderid  = do
   let symbol = "ADAUSDT"
   let symboll = "ADAUSDT"
   curtimestamp <- getcurtimestamp
   runReq defaultHttpConfig $ do 
      let signature = BLU.fromString sk
      let passwdtxt = BC.pack Passwd.passwd
      let origClientOrderId = sellorderid
      --let origClientOrderId = orderid
      let params = 
            ("symbol" =: (symboll :: Text)) <>
            ("origClientOrderId" =: origClientOrderId  ) <> 
            ("orderId" =: orderid  ) <> 
            ("timestamp" =: (show curtimestamp ))

      let abody = BLU.fromString $ NTB.urlEncodeVars [("symbol",symbol),("origClientOrderId",origClientOrderId),("orderId",orderid),("timestamp",show curtimestamp)  ] 
      let ares = showDigest(hmacSha256 signature abody)
      let httpparams = 
            (header "X-MBX-APIKEY" passwdtxt ) <>
            ("signature" =: (T.pack ares :: Text ))
      let ouri = "https://fapi.binance.com/fapi/v1/order"  
      let auri=ouri<>(T.pack "?signature=")<>(T.pack ares)
      liftIO $ logact logByteStringStdout $ BC.pack  $ show ("cancelo ----",orderid)
      uri <- URI.mkURI auri 
      let (url, options) = fromJust (useHttpsURI uri)
      let areq = req DELETE url (ReqBodyUrlEnc params) ignoreResponse  httpparams
      _ <- areq
      liftIO $ logact logByteStringStdout $ BC.pack  $ show ("cancelo ----",orderid)
      return ()
    --cancel all the order ,if  any more need can use api cancel detail order
   return () 

takeorder :: String -> Integer -> Double -> IO ()
takeorder a b c = do 
   let symbol = "ADAUSDT"
   let symboll = "ADAUSDT"
   let side = a -- "BUY" "SELL"
   let stype = "LIMIT"
   let timeinforce = "GTC"
   let timeinforcee = "GTC"
   let newClientOrderId = case side of 
                             "BUY"  -> buyorderid
                             "SELL" -> sellorderid
   let quantity = if b > 10 then b else 10 :: Integer
   
   let price = c :: Double
   curtimestampl <- (round . (* 1000) <$> getPOSIXTime )
   let curtimestamp = curtimestampl :: Integer
   runReq defaultHttpConfig $ do 
      let signature = BLU.fromString sk
      let params = 
             "symbol" =: (symboll :: Text) <>
             "side" =: (side) <>
             "type" =: (stype) <>
             "quantity" =: (quantity) <>
             "price" =: (showdouble price) <>
             "newClientOrderId" =: (newClientOrderId) <>
             "timeInForce" =: (timeinforcee :: Text) <>
             "timestamp" =: (curtimestamp)

      let abody = BLU.fromString $ NTB.urlEncodeVars [("symbol",symbol),("side",side),("type",stype),("quantity",show quantity),("price",showdouble price),("newClientOrderId",newClientOrderId),("timeInForce",timeinforce),("timestamp",show curtimestamp)] 
      let ares = showDigest(hmacSha256 signature abody)
      let passwdtxt = BC.pack Passwd.passwd
      let httpparams = 
            (header "X-MBX-APIKEY" passwdtxt ) <>
            ("signature" =: (T.pack ares :: Text ))
      
      let ouri = "https://fapi.binance.com/fapi/v1/order"  
      let auri=ouri<>(T.pack "?signature=")<>(T.pack ares)
      uri <- URI.mkURI auri 
      let (url, options) = fromJust (useHttpsURI uri)
      let areq = req POST url (ReqBodyUrlEnc params) ignoreResponse httpparams
      liftIO $ logact logByteStringStdout $ BC.pack  $ show ("bef take order!--")
      response <- areq
      return ()
   
parsekline :: String -> IO (DpairMserie) 
parsekline nstr  = runReq defaultHttpConfig $ do
    let ouri = https "fapi.binance.com" /: "fapi" /: "v1" /: "klines"  
    let symbol = "ADAUSD"
    let tnstr = nstr 
    let limit = 3
    let params = 
          "symbol" =: ("ADAUSDT" :: Text) <>
          "interval" =: (tnstr ) <>
          "limit" =: (24 :: Int)
    areq <- req GET ouri NoReqBody lbsResponse params
    let breq = responseBody areq
    let creq =  (A.decode breq) :: Maybe Mseries
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
    let signature = BLU.fromString Passwd.sk
    let ae = fromJust a 
    let aa = BL.toString ae 
    let ouri = https "fapi.binance.com" /: "fapi" /: "v1" /: "listenKey"  
    --let ouri = https "fapi.binance.com" /: "fapi" /: "v1" /: "userDataStream"  
    
    let passwdtxt = BC.pack Passwd.passwd
    let params = 

          (header "X-MBX-APIKEY" passwdtxt ) <>
           "listenKey" =: (T.pack aa :: Text)

    let abody = BLU.fromString $ NTB.urlEncodeVars [("listenKey",aa)] 
    let ares = showDigest(hmacSha256 signature abody)
    --let passwdtxt = BC.pack Passwd.passwd
    --let httpparams = 
          --(header "X-MBX-APIKEY" passwdtxt ) <>
    --      "listenKey" =: (T.pack aa :: Text)
          --("signature" =: (T.pack ares :: Text )) 
    areq <- req PUT ouri  NoReqBody  lbsResponse params
    --liftIO $ print (areq)
    return ()
    --liftIO $ print (areq)


data WSevent = WSevent {
      wstream :: String,
      wsdata :: Value
} deriving (Show,Generic)

instance FromJSON WSevent where
   parseJSON (Object v) = do
      WSevent <$> (v .: "stream") 
              <*> (v .: "data")
   parseJSON _ = mzero

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

getlistfrdep :: Depseries -> (Int, ([(Double,BL.ByteString)],[(Double,BL.ByteString)]))
getlistfrdep (Depseries a ) = a 
--instance  Show Mseries 

data Depseries = Depseries   (Int ,([(Double,BL.ByteString)],[(Double,BL.ByteString)]))  deriving (Show,Generic) 

data Wdepseries = Wdepseries {
  --    depu  :: Int,
  --    depU  :: Int,
  --    deppu :: Int,
  --    bidsh :: [(Double,BL.ByteString)],
  --    asksh :: [(Double,BL.ByteString)]
        tdata :: String
} deriving (Show,Generic) 

instance FromJSON Wdepseries where 
    parseJSON (Object o) = do
       --depthdata     <- (o .: "data")
      -- depthevtdata     <- (o .: "adausdt@depth@500ms")
      -- uutimee       <- depthdata .: "U"
      -- utimee        <- depthdata .: "u"
      -- putimee       <- depthdata .: "pu"
      -- let uutime  = read uutimee :: Int
      -- let utime   = read  utimee :: Int
      -- let putime  = read putimee :: Int

      -- bidlist      <- depthdata .: "b"
      -- asklist      <- depthdata .: "a"
      -- bidsListo    <- mapM parseJSON $ V.toList bidlist
      -- asksListo    <- mapM parseJSON $ V.toList asklist
      -- let bidsList = listranform bidsListo
      -- let asksList = listranform asksListo
       return $ Wdepseries $show o  --uutime utime putime bidsList asksList 
    parseJSON _ = return $ Wdepseries "ttttt"

listranform :: [[String]] -> [(Double,BL.ByteString)]
listranform al = [ (read (i!!1)::Double, BLL.toStrict $ BLU.fromString (i!!0) )|i<-al ] 

instance FromJSON Depseries where 
    parseJSON (Object o) = do
       bids      <- o .: "bids" 
       asks      <- o .: "asks"
       lastupdid <- o .: "lastUpdateId"
       bidsListo <- mapM parseJSON $ V.toList bids
       asksListo <- mapM parseJSON $ V.toList asks
       let bidsList = listranform bidsListo
       let asksList = listranform asksListo
       return $ Depseries (lastupdid,(bidsList,asksList))
    parseJSON _ = mzero

data HStick = HStick {
      st :: Integer,
      op :: String,
      cp :: String,
      hp :: String,
      lp :: String
} deriving (Show,Generic)

instance FromJSON HStick where
   parseJSON (Array v) = do
          st <- parseJSON $ v V.! 0
          op <- parseJSON $ v V.! 1
          hp <- parseJSON $ v V.! 2
          lp <- parseJSON $ v V.! 3
          cp <- parseJSON $ v V.! 4
          return $ HStick st op hp lp cp
   parseJSON _ = mzero


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
----  parseJSON (Object o) = 
--    Stickwebsocketdata <$> (o .: "stream")
--                       <*> (o .: "data")
--  parseJSON _ = mzero
-----------------------------
