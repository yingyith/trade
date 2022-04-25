{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
import Network.Wuss
import Database.Redis as R
import Control.Concurrent (myThreadId ,forkIO ,threadDelay,ThreadId,killThread)
import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Concurrent.STM.TBQueue
import Control.Lens
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
import Events
import Data.Text.Encoding
import Logger
import Order
import System.IO
import System.Exit
import System.Log.Logger 
import System.Log.Handler (setFormatter)
import System.Log.Handler.Syslog
import System.Log.Handler.Simple
import System.Log.Formatter
import System.Posix.Process
import System.Posix.Types
import System.Process
import System.Posix.Signals
import System.Posix
import Colog (LogAction,logByteStringStdout)
import Myutils

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
    minSticksToCache conn
    getspotbaltoredis conn
   -- takeorder
    --personal account
    --stream?streams=ethusdt@kline_1m/listenKey
    --runSecureClient "stream.binance.com" 9443 aimss  ws
    --runSecureClient "fstream.binance.com" 443 aimss  ws
    --liftIO $ print ("connect to websocket------")
   -- let logPath = "/root/trade/1.log"
   -- myStreamHandler <- streamHandler stderr INFO
   -- myFileHandler <- fileHandler logPath INFO
   -- let myFileHandler' = withFormatter myFileHandler
   -- let myStreamHandler' = withFormatter myStreamHandler
   -- let flog = "myapp"
   -- updateGlobalLogger flog (setLevel INFO)
   -- updateGlobalLogger flog (setHandlers [myFileHandler', myStreamHandler'])
    --infoM flog $ "Logging to " ++ logPath
    sid <- forkProcess $ do runSecureClient "fstream.binance.com" 443 aimss  ws
    --liftIO $ print ("after ws----")
   -- forever $ do 
   --    res <- expirepredi conn 150000
   --    let preres = fst res
   --    let sid  = case preres of 
   --                   True   -> do 
   --                                sendbye connection conn 0 ctrll sid 
   --                                removeAllHandlers
   --                                sid <- forkProcess $ do runSecureClient "fstream.binance.com" 443 aimss  ws
   --                                return sid
   --                   False  -> return sid
   --    case preres of 
   --        True   -> do 
   --                     sendbye connection conn 0 ctrll sid 
   --                     removeAllHandlers
   --                     sid <- forkProcess $ do runSecureClient "fstream.binance.com" 443 aimss  ws
   --                     return sid
   --        False  -> return sid

   --    sendbye connection conn 0 ctrll sid 
   --    threadDelay 60000000
    retryOnFailure conn sid
    
expirepredi :: R.Connection -> Integer -> IO (Bool,Integer)
expirepredi conn min = do 
    beftimee <- runRedis conn gettimefromredis  
    let beftime = read $ BLU.toString $ BLL.fromStrict $ fromJust $ fromRight (Nothing) beftimee :: Integer
    curtime <- getcurtimestamp
    case (curtime-beftime) of 
         y|y> mins -> return (True , curtime-beftime)
         _         -> return (False, curtime-beftime)
        where mins = min


retryOnFailure :: R.Connection  -> (ProcessID) ->  IO ()
retryOnFailure conn  sid = do
    threadDelay 40000000
    res <- expirepredi conn 120000
    let preres = fst res
    --infoM "myapp" $ show $ snd res
    case preres of 
       True -> do  
                 --infoM "myapp" $ show $ snd res
                 --logact logByteStringStdout $ B.pack $ show ("kill bef thread!",snd res)
                 signalProcess sigKILL sid
                 --infoM "myapp" $ show $ "after kill"
                 --logact logByteStringStdout $ B.pack $ show ("kill bef thread!",snd res)
                 threadDelay 6000000
                 aid <- forkProcess $ do runSecureClient "fstream.binance.com" 443 "/" ws 
                 --threadDelay 120000
                 retryOnFailure conn  aid 
       False ->  threadDelay 6000000                                                            


sendbye  ::  NC.Connection -> R.Connection -> Int ->  PubSubController -> IO () -- -> (System.Posix.Types.ProcessID)  -> IO ()
sendbye wconn conn ac ctrl  = do
    res <- expirepredi conn 120000
    let preres = fst res 
    --let timediff = snd res
    --infoM "time" $ show timediff 
    case preres of 
      True   -> do
                     void $ NW.sendClose wconn (B.pack "Bye!")
                     --signalProcess sigKILL mpid
                     removeAllHandlers
                     --throwIO ConnectionClosed
                     die "time to kill monitor process to async!"
      False  -> return ()
    sendbye wconn conn (ac+1) ctrl 
    --NW.sendClose wconn (B.pack "Bye!")
    --liftIO $ print ("it is in sendbye aft sendbye")
    --threadDelay 50000000

               
      --unless ((curtime-400) > beftime) $ do
      --    liftIO $ print ("bef sendbye")
      --    sendbye rconn wconn
          


--settodefredisstate side otype state orderid  pr quan grid  mergequan stamp = do 
ws :: ClientApp ()
ws connection = do
    --B.putStrLn "Connected!"
   -- logFileHandle <- openFile "/root/trade/1.log" ReadWriteMode
    ctrll <- newPubSubController [][]
    conn <- connect defaultConnectInfo
    connn <- connect defaultConnectInfo
    connnn <- connect defaultConnectInfo
    qryord <- queryorder
    qrypos <- querypos
    let bqryord = fst qryord
    let sqryord = snd qryord
    currtime <- getcurtimestamp 
    liftIO $ print ("fork async now!",currtime)
    let curtime = fromInteger currtime ::Double
    liftIO $ print ("fork async now!",qrypos,bqryord,sqryord)
    case (qrypos,bqryord,sqryord) of 
       ([] ,[] ,[] ) ->  do
                             let astate = show $ fromEnum Done
                             runRedis conn (settodefredisstate "SELL" "Done" astate "0"  0   0      0  0  curtime)-- set to Done prepare 
                             liftIO $ print ("fork async now!")
       ([] ,_  ,[] ) ->  do -- cancel the order ,set to prepare
                             let astate = show $ fromEnum Done
                             mapM_ funcgetorderid  sqryord
                             runRedis conn (settodefredisstate "SELL" "Done" astate "0"  0   0      0  0  curtime)-- set to Done prepare 
                             return () 
       ([] ,[] ,_  ) ->  do -- cannot appear ,cancel the order,set to prepare 
                             let astate = show $ fromEnum Done
                             mapM_ funcgetorderid  bqryord
                             runRedis conn (settodefredisstate "SELL" "Done" astate "0"  0   0      0  0  curtime)-- set to Done prepare 
                             return ()
       ([] ,_  ,_  ) ->  do -- cannot appear ,cancel the order,set to prepare
                             let astate = show $ fromEnum Done
                             mapM_ funcgetorderid  bqryord
                             mapM_ funcgetorderid  sqryord
                             runRedis conn (settodefredisstate "SELL" "Done" astate "0"  0   0      0  0  curtime)-- set to Done prepare 
                             return ()
       (_  ,[] ,[] ) ->  do -- set to halfdone
                             let astate = show $ fromEnum HalfDone
                             (quan,pr) <- funcgetposinf qrypos
                             liftIO $ print ("fork async now!!!",quan,pr)
                             runRedis conn (settodefredisstate "BUY" "Hdone" astate "0"  pr  quan   0  0  curtime)-- set to Done prepare 
                             return ()
       (_  ,[] ,_  ) ->  do-- set to cproinit --detail judge merge or init
                             let astate = show $ fromEnum HalfDone
                             mapM_ funcgetorderid  bqryord
                             (quan,pr) <- funcgetposinf qrypos
                             runRedis conn (settodefredisstate "BUY" "Hdone" astate "0"  pr  quan   0  0  curtime)-- set to Done prepare 
                             return ()
       (_  ,_  ,[] ) ->  do-- set to promerge
                             let astate = show $ fromEnum HalfDone
                             mapM_ funcgetorderid  sqryord
                             (quan,pr) <- funcgetposinf qrypos
                             runRedis conn (settodefredisstate "BUY" "Hdone" astate "0"  pr  quan   0  0  curtime)-- set to Done prepare 
                             return ()
       (_  ,_  ,_  ) ->  do-- not allow to appear,cancel the border and sorder,set state to hlddone 
                             let astate = show $ fromEnum HalfDone
                             mapM_ funcgetorderid  bqryord
                             mapM_ funcgetorderid  sqryord
                             (quan,pr) <- funcgetposinf qrypos
                             runRedis conn (settodefredisstate "BUY" "Hdone" astate "0"  pr  quan   0  0  curtime)-- set to Done prepare 
                             return ()


    let ordervari = Ordervar True 0 0 0
    let orderVar = newTVarIO ordervari-- newTVarIO Int
    sendthid <- myThreadId 
    q <- newTBQueueIO 30 :: IO (TBQueue Opevent)

    withAsync (publishThread conn connection orderVar sendthid) $ \_pubT -> do
        --threadDelay 4000000
        withAsync (handlerThread connn ctrll orderVar) $ \_handlerT -> do
           void $ addChannels ctrll [] [("sndc:*"     , sndtocacheHandler )]
           void $ addChannels ctrll [] [("minc:*"     , mintocacheHandler )]
           void $ addChannels ctrll [] [("analysis:*" , analysisHandler   )]
           void $ addChannels ctrll [] [("order:*"    , opclHandler  q connn   )]
           void $ addChannels ctrll [] [("listenkey:*", listenkeyHandler  )]
           threadDelay 1000000
        --threadDelay 1000000
           forkIO $ detailopHandler q 
        --sendbye connection conn 0 ctrll 
    forever  $ do
       threadDelay 50000000
    return ()

