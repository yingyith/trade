{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
import Network.Wuss
import Database.Redis as R
import Control.Concurrent (myThreadId ,forkIO ,threadDelay )
import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Monad (forever, unless, void)
import Control.Exception (catch,throwIO)
import Colog (usingLoggerT,cmap,fmtMessage,logTextStdout,logTextHandle,logInfo)
import Data.Text (Text, pack)
import Network.WebSockets as NW (ClientApp, receiveData, sendClose, sendTextData,ConnectionException( ConnectionClosed ))
import Network.WebSockets.Connection as NC
import Control.Monad
import Control.Monad.IO.Class
import Data.Aeson
import Data.Aeson.Lens
import Data.Aeson.Types
import Data.Either
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
import Data.ByteString.Lazy as BLL
import qualified Data.ByteString.UTF8 as BL
import Data.ByteString.Lazy.Char8
import qualified Data.ByteString.Char8 as B
import qualified Text.URI as URI
import Httpstructure
import Passwd
import Redispipe
import Rediscache
import Data.Text.Encoding
import Logger
import System.IO
import System.Log.Logger 
import System.Log.Handler (setFormatter)
import System.Log.Handler.Syslog
import System.Log.Handler.Simple
import System.Log.Formatter
import System.Posix.Process
import System.Posix.Types
import System.Process
import System.Posix.Signals

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
        --liftIO $ print ares
        
        let ouri = "https://fapi.binance.com/fapi/v1/listenKey"  
        --let ouri = "https://api.binance.com/api/v3/userDataStream"  
        let auri=ouri<>(T.pack "?signature=")<>(T.pack ares)
        --liftIO $ print auri
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
        --liftIO $ print result
        --liftIO $ print (responseBody response :: Object)
        let ares = fromJust $  parseMaybe (.: "listenKey") result :: String
        pure ares
    --liftIO $ print (aas)
    conn <- connect defaultConnectInfo
    nowtime <- getcurtimestamp
    runRedis conn (liskeytoredis aas nowtime)
    --let aimss = "/stream?streams=adausdt@kline_1m&listenkey=" ++ aas -----------------------------------------------
    --liftIO $ print (aimss)
    let aimss = "/stream?streams=adausdt@kline_1m/"  ++ aas -----------------------------------------------
   -- let aimss = "/stream?streams=adausdt@kline_1m/"  -----------------------------------------------
    --let aimss = "/ws/" ++aas -----------------------------------------------
    --let aimss = "/ws/streams=btcusdt@markPrice/"++ "&listenkey="  ++ aas -----------------------------------------------
    --let aimss = "/ws/adausdt@kline_1m/"++ aas ++ "&listenkey="  ++ aas -----------------------------------------------
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
    --liftIO $ print ("connect to websocket------")
    catch (runSecureClient "fstream.binance.com" 443 aimss  ws)(\e ->
          if e == ConnectionClosed 
          then do
                 retryOnFailure conn
          else do 
                 retryOnFailure conn

          )
    
expirepredi :: R.Connection -> Integer -> IO Bool
expirepredi conn min = do 
                 beftimee <- runRedis conn gettimefromredis  
                 let beftime = read $ BLU.toString $ BLL.fromStrict $ fromJust $ fromRight (Nothing) beftimee :: Integer
                 curtime <- getcurtimestamp
                 case (curtime-beftime) of 
                      y|y> mins -> return True
                      _         -> return False
                     where mins = min

retryOnFailure :: R.Connection ->  IO ()
retryOnFailure conn  = forever $ do
                                    preres <- expirepredi conn 150000
                                    case preres of 
                                       True ->  runSecureClient "fstream.binance.com" 443 "/" ws `catch`   (\e -> 
                                                                                                             if e == ConnectionClosed 
                                                                                                             then retryOnFailure conn 
                                                                                                             else return ())
                                       False -> return ()                                                            

sendbye  ::  NC.Connection -> R.Connection -> Int ->  PubSubController -> Maybe (System.Posix.Types.ProcessID)  -> IO ()
sendbye wconn conn ac ctrl mpid = do
      ares <- case ac of 
                 x|x==0 -> do    
                             liftIO $ print ("it is in sendbye ")
        --                     warningM "myapp" "bef withasync" 
                             let ordervari = Ordervar True 0 0 0
                             let orderVar = newTVarIO ordervari-- newTVarIO Int
                             sendthid <- myThreadId 

                             piid <- forkProcess $ withAsync (publishThread conn wconn orderVar sendthid) $ \_pubT -> do
                                                     withAsync (handlerThread conn ctrl orderVar) $ \_handlerT -> do
                                                        void $ addChannels ctrl [] [("order:*", opclHandler)]
                                                        void $ addChannels ctrl [] [("cache:*", cacheHandler)]
                                                        void $ addChannels ctrl [] [("listenkey:*", listenkeyHandler)]
                                                        void $ addChannels ctrl [] [("skline:*", sklineHandler)]
                                                        void $ addChannels ctrl [] [("analysis:*", analysisHandler)]
                             let nmpid = Just piid
                             threadDelay 1000000
                             conn <- connect defaultConnectInfo
                             liftIO $ print ("it is aft async ")
                             return nmpid
       --                      warningM "myapp" "aft withasync" 
                             --sendbye wconn conn (ac+1) ctrl nmpid



                 x|x>0  -> do 
                             preres <- expirepredi conn 300000
                             case preres of 
                               True   -> do
                                              void $ NW.sendClose wconn (B.pack "Bye!")
                                              signalProcess sigKILL $ fromJust mpid
                                              throwIO ConnectionClosed
                               False  -> return ()
                                        -- case ac of 
                                        --    x|x==5 -> do 
                                        --                  void $ NW.sendClose wconn (B.pack "Bye!")
                                        --                  liftIO $ print (beftime ,curtime,ac)
                                        --                  throwIO ConnectionClosed
                                        --                  return ()
                                        --    _     -> return ()
                             return mpid
                           `catch` (\e ->
                              if e == ConnectionClosed 
                              then do
   --                                  warningM "myapp" "it is closed!" 
    --                                 warningM "myapp" $ show e
                                     liftIO $ print ("it is closed! ")
                                     throwIO e

                              else do 
     --                                warningM "myapp" "other excep!" 
      --                               warningM "myapp" $ show e
                                     liftIO $ print ("it is other ep! ")
                                     throwIO e
                                     )

      sendbye wconn conn (ac+1) ctrl ares
    --NW.sendClose wconn (B.pack "Bye!")
    --liftIO $ print ("it is in sendbye aft sendbye")
    --threadDelay 50000000

               
      --unless ((curtime-400) > beftime) $ do
      --    liftIO $ print ("bef sendbye")
      --    sendbye rconn wconn
          
ws :: ClientApp ()
ws connection = do
    --B.putStrLn "Connected!"
   -- logFileHandle <- openFile "/root/trade/1.log" ReadWriteMode
    ctrll <- newPubSubController [][]
    conn <- connect defaultConnectInfo
    let logPath = "/root/trade/1.log"
    myStreamHandler <- streamHandler stderr INFO
    myFileHandler <- fileHandler logPath INFO
    let myFileHandler' = withFormatter myFileHandler
    let myStreamHandler' = withFormatter myStreamHandler
    let log = "myapp"
    updateGlobalLogger log (setLevel INFO)
    updateGlobalLogger log (setHandlers [myFileHandler', myStreamHandler'])
    infoM log $ "Logging to " ++ logPath
    --
    --let ordervari = Ordervar True 0 0 0
    --let orderVar = newTVarIO ordervari-- newTVarIO Int
   -- usingLoggerT 
   --   (cmap
   --     fmtMessage
   --     (logTextHandle logFileHandle )) $ do 
   --   logInfo "bef sendbye"
    sendbye connection conn 0 ctrll Nothing 

 --   sendthid <- catch (forkIO $ do 
 --                          threadDelay 1000000 
 --                          forever (sendbye connection)) (\e ->
 --                                                             if e == ConnectionClosed 
 --                                                             then do
 --                                                                    liftIO $ print ("11s",e)
 --                                                                    throwIO e
 --                                                                    return nowthreadid

 --                                                             else do 
 --                                                                    liftIO $ print ("21s",e)
 --                                                                    throwIO e
 --                                                                    return nowthreadid
 --                                                                    )

 --   catch (withAsync (publishThread conn connection orderVar sendthid) $ \_pubT -> do
 --            withAsync (handlerThread conn ctrl orderVar) $ \_handlerT -> do
 --                void $ addChannels ctrl [] [("order:*", opclHandler)]
 --                void $ addChannels ctrl [] [("cache:*", cacheHandler)]
 --                void $ addChannels ctrl [] [("listenkey:*", listenkeyHandler)]
 --                void $ addChannels ctrl [] [("skline:*", sklineHandler)]
 --                void $ addChannels ctrl [] [("analysis:*", analysisHandler)]) (\e ->
 --                                                                                    if e == ConnectionClosed 
 --                                                                                    then do
 --                                                                                           liftIO $ print ("it is retry!")
 --                                                                                           liftIO $ print e
 --                                                                                    else do 
 --                                                                                           liftIO $ print e
 --                                                                                           liftIO $ print ("it is2 retry!")
 --                                                                               )
    --threadDelay 5000000
   -- liftIO $ print ("??????")
   -- void . forkIO  $ forever (sendbye connection)
    --liftIO $ print ("it is ----!!!!")

