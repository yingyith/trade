{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
import Network.Wuss
import Database.Redis
import Control.Concurrent (forkIO)
import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Monad (forever, unless, void)
import Control.Exception (catch)
import Data.Text (Text, pack)
import Network.WebSockets as NW (ClientApp, receiveData, sendClose, sendTextData)
import Control.Monad
import Control.Monad.IO.Class
import Data.Aeson
import Data.Aeson.Lens
import Data.Aeson.Types
import Data.HashMap.Lazy (HashMap)
import Data.Maybe (fromJust)
import Data.Monoid ((<>))
import Data.Text  as T
import Data.Text.IO as T
import Data.Map
import GHC.Generics
import Network.HTTP.Req
import Data.Digest.Pure.SHA
import Data.ByteString.Lazy.UTF8 as BLU
import Data.ByteString.Lazy.Char8
import qualified Data.ByteString.Char8 as B
import qualified Text.URI as URI
import Httpstructure
import Passwd
import Redispipe
import Rediscache
import Data.Text.Encoding
import System.IO

--retryOnFailure ws = runSecureClient "ws.kraken.com" 443 "/" ws
--  `catch` (\e -> 
--     if 22 == 22-- ConnectionClosed
--         then retryOnFailure ws
--     else return ())


main :: IO ()
main =  
  do
    -----------------------------------------------
    --form query string 
    --hmac query string 
    --query string signature
    --X-MBX-APIKEY :apikey
    --
    aas<-runReq defaultHttpConfig $ do
--传递querystr 经过hmac sha256加密增加sinnature为querystr参数，传递
        let astring = BLU.fromString "123"
        let signature = BLU.fromString "234"
        let ares = showDigest(hmacSha256 signature astring)
        liftIO $ print ares
        
        let ouri = "https://fapi.binance.com/fapi/v1/listenKey"  
        --let ouri = "https://api.binance.com/api/v3/userDataStream"  
        let auri=ouri<>(T.pack "?signature=")<>(T.pack ares)
        liftIO $ print auri
        --增加对astring的hmac的处理 
        uri <- URI.mkURI auri 
        let (url, options) = fromJust (useHttpsURI uri)
        let passwdtxt = B.pack Passwd.passwd
        let areq = req POST url NoReqBody jsonResponse (header "X-MBX-APIKEY" passwdtxt )
        --how to change bs to json
        response <- areq
       -- liftIO $ B.putStrLn (responseBody response)
        --init redis cache dict
        --liftIO $ print (ages)
        --liftIO $ print t
        let ages = sticks!"5min"
        --liftIO $ print ages
        -----------------------
        --liftIO $ print (response)
        let result = responseBody response :: Object
        liftIO $ print result
        --liftIO $ print (responseBody response :: Object)
        let ares = fromJust $  parseMaybe (.: "listenKey") result :: String
        pure ares
    liftIO $ print (aas)
    conn <- connect defaultConnectInfo
    runRedis conn (liskeytoredis aas)
    let aimss = "/stream?streams=adausdt@kline_1m&listenkey=" ++ aas -----------------------------------------------
    --liftIO $ print (aimss)
    --let aimss = "/stream?streams=adausdt@kline_1m/"  ++ aas -----------------------------------------------
   -- let aimss = "/stream?streams=adausdt@kline_1m/"  -----------------------------------------------
    --let aimss = "/ws/" ++aas++"?listenkey="  ++ aas -----------------------------------------------
    --let aimss = "/ws/streams=btcusdt@markPrice/"++ "&listenkey="  ++ aas -----------------------------------------------
    --let aimss = "/ws/adausdt@kline_1m/"++ "&listenkey="  ++ aas -----------------------------------------------
    --"send ping every 30mins"
    -- pass listen key to getSticksToCache and set key ,then do detail on sub handler ,update
    -- loop every 30mins
    getSticksToCache conn
    getspotbaltoredis conn
   -- takeorder
    --personal account
    --stream?streams=ethusdt@kline_1m/listenKey
    --runSecureClient "stream.binance.com" 9443 aimss  ws
    --runSecureClient "fstream.binance.com" 443 aimss  ws
    liftIO $ print ("connect to websocket------")
    runSecureClient "fstream-auth.binance.com" 443 aimss  ws
--issue streams = <listenKey> -- add user Data Stream
ws :: ClientApp ()
ws connection = do
    B.putStrLn "Connected!"
    --ctrl <- newPubSubController [("order:*",opclHandler)][]
    ctrl <- newPubSubController [][]
    conn <- connect defaultConnectInfo
    liftIO $ print ("/////////////////////")
    --
    let ordervari = Ordervar True 0 0 0
    let orderVar = newTVarIO ordervari-- newTVarIO Int

    withAsync (publishThread conn connection orderVar) $ \_pubT -> do
      withAsync (handlerThread conn ctrl orderVar) $ \_handlerT -> do
        liftIO $ print ("ssss----------")
        void $ addChannels ctrl [] [("order:*", opclHandler)]
        void $ addChannels ctrl [] [("cache:*", cacheHandler)]
        void $ addChannels ctrl [] [("listenkey:*", listenkeyHandler)]
        void $ addChannels ctrl [] [("skline:*", sklineHandler)]
        void $ addChannels ctrl [] [("analysis:*", analysisHandler)]

    let loop = do
            line <- T.getLine
            print ("jjjjjj" )
            unless (T.null line) $ do
                print (line )
                let reline = line
                sendTextData connection (line)
                loop
    loop

    sendClose connection (B.pack "Bye!")
