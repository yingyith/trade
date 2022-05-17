{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
import Network.Wuss
import Database.Redis as R
import Control.Concurrent (myThreadId ,forkIO ,threadDelay,ThreadId,killThread)
import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Concurrent.STM.TVar
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
import Data.Aeson.Types as DAT
import qualified Data.HashMap  as DHM
import Data.Either
import qualified  Data.Vector  as DV  
import Data.HashMap.Lazy (HashMap)
import Data.Maybe (fromJust)
import Data.Monoid ((<>))
import Data.Text  as T
import Data.Text.IO as T
import Data.Map
import GHC.Generics
import Prelude as PM
import Lib
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
import Analysistructure
import Mobject


main :: IO ()
main =  
  do
    aas<-runReq defaultHttpConfig $ do
        let astring = BLU.fromString "123"
        let signature = BLU.fromString "234"
        let ares = showDigest(hmacSha256 signature astring)
        let ouri = "https://fapi.binance.com/fapi/v1/listenKey"  
        let auri=ouri<>(T.pack "?signature=")<>(T.pack ares)
        uri <- URI.mkURI auri 
        let (url, options) = fromJust (useHttpsURI uri)
        let passwdtxt = B.pack Passwd.passwd
        let areq = req POST url NoReqBody jsonResponse (header "X-MBX-APIKEY" passwdtxt )
        response <- areq
        let ages = sticks!"5min"
        let result = responseBody response :: Object
        let ares = fromJust $  parseMaybe (.: "listenKey") result :: String
        pure ares
    conn <- connect defaultConnectInfo
    nowtime <- getcurtimestamp
    runRedis conn (liskeytoredis aas nowtime)
    --let aimss = "/stream?streams=adausdt@kline_1m&listenkey=" ++ aas -----------------------------------------------
    --liftIO $ print (aimss)
    let aimss = "/stream?streams=adausdt@kline_1m/adausdt@depth@500ms/"  ++ aas -----------------------------------------------
    minSticksToCache conn
    getspotbaltoredis conn
    sid <- forkProcess $ do runSecureClient "fstream.binance.com" 443 aimss  ws
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
    case preres of 
      True   -> do
                     void $ NW.sendClose wconn (B.pack "Bye!")
                     --signalProcess sigKILL mpid
                     removeAllHandlers
                     --throwIO ConnectionClosed
                     die "time to kill monitor process to async!"
      False  -> return ()
    sendbye wconn conn (ac+1) ctrl 

--depthitemtoredis :: (DV.Vector Array)   ->   (Double,String)
--depthitemtoredis itemo  = ((outString $ (!!0) itemo) ,(read $ outString $ (!!1) itemo :: Double))



initpos ::  IO (Double,(Integer,Double))
initpos  = do 
    qrypos     <- querypos
    (quan,pr)  <- funcgetposinf qrypos
    let accugrid = getnewgrid quan  
    return (accugrid,(quan,pr))

initbal :: R.Connection -> Double -> Integer -> Double -> [Value] -> [Value] -> Double -> IO String
initbal conn accugrid quan pr bqryord sqryord curtime= do 
    resstate <-  case (quan==0,bqryord,sqryord) of 
                       (True  ,[] ,[] ) ->  do
                                             let astate = show $ fromEnum Done
                                             runRedis conn (settodefredisstate "SELL" "Done" astate "0"  0   0      accugrid  0  curtime)-- set to Done prepare 
                                             return astate
                       (True  ,_  ,[] ) ->  do -- cancel the order ,set to prepare
                                             let astate = show $ fromEnum Done
                                             mapM_ funcgetorderid  sqryord
                                             runRedis conn (settodefredisstate "SELL" "Done" astate "0"  0   0      accugrid  0  curtime)-- set to Done prepare 
                                             return astate
                       (True  ,[] ,_  ) ->  do -- cannot appear ,cancel the order,set to prepare 
                                             let astate = show $ fromEnum Done
                                             mapM_ funcgetorderid  bqryord
                                             runRedis conn (settodefredisstate "SELL" "Done" astate "0"  0   0      accugrid  0  curtime)-- set to Done prepare 
                                             return astate
                       (True  ,_  ,_  ) ->  do -- cannot appear ,cancel the order,set to prepare
                                             let astate = show $ fromEnum Done
                                             mapM_ funcgetorderid  bqryord
                                             mapM_ funcgetorderid  sqryord
                                             runRedis conn (settodefredisstate "SELL" "Done" astate "0"  0   0      accugrid  0  curtime)-- set to Done prepare 
                                             return astate
                       (False ,[] ,[] ) ->  do -- set to halfdone
                                             let astate = show $ fromEnum HalfDone
                                             runRedis conn (settodefredisstate "BUY" "Hdone" astate "0"  pr  quan   accugrid  0  curtime)-- set to Done prepare 
                                             return astate
                       (False ,[] ,_  ) ->  do-- set to cproinit --detail judge merge or init
                                             let astate = show $ fromEnum HalfDone
                                             mapM_ funcgetorderid  bqryord
                                             runRedis conn (settodefredisstate "BUY" "Hdone" astate "0"  pr  quan   accugrid  0  curtime)-- set to Done prepare 
                                             return astate
                       (False ,_  ,[] ) ->  do-- set to promerge
                                             let astate = show $ fromEnum HalfDone
                                             mapM_ funcgetorderid  sqryord
                                             runRedis conn (settodefredisstate "BUY" "Hdone" astate "0"  pr  quan   accugrid  0  curtime)-- set to Done prepare 
                                             return astate
                       (False ,_  ,_  ) ->  do-- not allow to appear,cancel the border and sorder,set state to hlddoaccugride 
                                             let astate = show $ fromEnum HalfDone
                                             mapM_ funcgetorderid  bqryord
                                             mapM_ funcgetorderid  sqryord
                                             runRedis conn (settodefredisstate "BUY" "Hdone" astate "0"  pr  quan   accugrid  0  curtime)-- set to Done prepare 
                                             return astate
    return resstate
    
ws :: ClientApp ()
ws connection = do
    ctrll                  <- newPubSubController [][]
    conn                   <- connect defaultConnectInfo
    connn                  <- connect defaultConnectInfo
    connnn                 <- connect defaultConnectInfo
    connnnn                <- connect defaultConnectInfo
    (accugrid,(quan,pr))   <- initpos
    qryord                 <- queryorder
    currtime               <- getcurtimestamp 
    let curtime            =  fromInteger currtime ::Double
    let bqryord            =  fst qryord
    let sqryord            =  snd qryord
    initostate             <- initbal conn accugrid quan pr bqryord sqryord curtime
    depthdata              <- initupddepth conn
    depthtvar              <- newTVarIO depthdata
    orderst                <- newTVarIO initostate
    let ordervari          =  Ordervar True 0 0 0
    let orderVar           =  newTVarIO ordervari-- newTVarIO Int
    sendthid               <- myThreadId 
    qws                    <- newTBQueueIO 200 :: IO (TBQueue Cronevent)
    qord                   <- newTBQueueIO 30  :: IO (TBQueue Opevent)
    qanalys                <- newTBQueueIO 30  :: IO (TBQueue Cronevent)

    withAsync (publishThread qws conn connection orderVar sendthid) $ \_pubT -> do
        withAsync (handlerThread connn ctrll orderVar) $ \_handlerT -> do
           void $ addChannels ctrll [] [("sndc:*"     , sndtocacheHandler qanalys depthtvar  )]
           void $ addChannels ctrll [] [("minc:*"     , mintocacheHandler                    )]
           void $ addChannels ctrll [] [("order:*"    , opclHandler  qord orderst            )]
           void $ addChannels ctrll [] [("analysis:*" , analysisHandler qanalys depthtvar    )]
           void $ addChannels ctrll [] [("listenkey:*", listenkeyHandler                     )]
           void $ addChannels ctrll [] [("depth:*"    , sndtocacheHandler qanalys depthtvar  )]
           threadDelay 900000
           forkIO $ detailpubHandler qws connnnn
           threadDelay 100000
           forkIO $ detailopHandler qord orderst  connn
           forkIO $ detailanalysHandler qanalys connnn depthtvar orderst
        --sendbye connection conn 0 ctrll 
    forever  $ do
       threadDelay 50000000
    return ()

