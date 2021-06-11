{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
import Wuss
import Control.Concurrent (forkIO)
import Control.Monad (forever, unless, void)
import Control.Exception (catch)
import Data.Text (Text, pack)
import Network.WebSockets (ClientApp, receiveData, sendClose, sendTextData)
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
import GHC.Generics
import Network.HTTP.Req
import Data.Digest.Pure.SHA
import Data.ByteString.Lazy.UTF8 as BLU
import Data.ByteString.Lazy.Char8
import qualified Data.ByteString.Char8 as B
import qualified Text.URI as URI
import Httpstructure
import Passwd

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
    runReq defaultHttpConfig $ do
	   --传递querystr 经过hmac sha256加密增加sinnature为querystr参数，传递
	   let astring = BLU.fromString "123"
           let signature = BLU.fromString "234"
           let ares = showDigest(hmacSha256 signature astring)
           liftIO $ print ares
           
           let ouri = "https://api.binance.com/api/v3/userDataStream"  
           let auri=ouri<>(T.pack "?signature=")<>(T.pack ares)
           liftIO $ print auri
           --增加对astring的hmac的处理 
           uri <- URI.mkURI auri 
           let (url, options) = fromJust (useHttpsURI uri)
           let passwdtxt = B.pack Passwd.passwd
           let areq = req POST url NoReqBody jsonResponse (header "X-MBX-APIKEY" passwdtxt )
           response <- areq
           let result = responseBody response :: Object
           --liftIO $ print (responseBody response :: Object)
           let ares = fromJust $  parseMaybe (.: "listenKey") result :: String
           liftIO $ print (ares)
    -----------------------------------------------
    runSecureClient "stream.binance.com" 9443 "/stream?streams=ethusdt@kline_1m" ws

ws :: ClientApp ()
ws connection = do
    B.putStrLn "Connected!"

    void . forkIO . forever $ do
        message <- receiveData connection
        --print (message :: Text)
        T.putStrLn $ T.pack  $ "" ++ (show (Data.Aeson.decode message :: Maybe WebsocketRsp))
        print ("kkkkkkkkk" )


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
