{-# OPTIONS_GHC -Wno-unused-top-binds #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveAnyClass             #-}
{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE InstanceSigs               #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE PatternSynonyms            #-}
{-# LANGUAGE TypeApplications           #-}
module Logger
    ( 
     logd,
     logact,
     withFormatter
    ) where

import Prelude hiding (log)

import Control.Concurrent (threadDelay)
import Control.Exception (Exception)
import Control.Monad.IO.Class (MonadIO (..))
import Control.Monad.Reader (MonadReader, ReaderT (..))
import Data.Text.Internal as DTI
import Data.Text as T
import Data.ByteString (ByteString)

import Colog (HasLog (..), LogAction, Message, Msg (..), PureLogger, RichMsg (..), SimpleMsg (..),
              WithLog, cmap, cmapM, defaultFieldMap, fmtMessage, fmtRichMessageDefault,
              fmtSimpleRichMessageDefault, liftLogIO, log, logException, logInfo, logMessagePure,
              logMsg, logMsgs, logPrint, logStringStdout, logText, logTextStderr, logTextStdout,
              logWarning, pattern D, runPureLog, upgradeMessageAction, usingLoggerT, withLog,
              withLogTextFile, (*<), (<&), (>$), (>$<), (>*), (>*<), (>|<))

import System.IO
import System.Log.Logger (rootLoggerName, setHandlers, updateGlobalLogger,
                          Priority(INFO), Priority(WARNING), infoM, debugM,
                          warningM, errorM, setLevel)
import System.Log.Handler.Simple (fileHandler, streamHandler, GenericHandler)
import System.Log.Handler (setFormatter)
import System.Log.Formatter
import qualified Data.TypeRepMap as TM


withFormatter :: GenericHandler Handle -> GenericHandler Handle
withFormatter handler = setFormatter handler formatter
    -- http://hackage.haskell.org/packages/archive/hslogger/1.1.4/doc/html/System-Log-Formatter.html
    where formatter = simpleLogFormatter "[$time $loggername $prio] $msg"

showany :: Show a => a -> Text
showany a = T.pack $ show  a

logd :: (WithLog env Message m,Show a) => a ->m ()
logd exa = do
    logInfo $ showany exa

logact :: LogAction IO ByteString -> ByteString -> IO ()
logact log msg = log <& msg

simpleApp :: (MonadIO m, WithLog env SimpleMsg m) => m ()
simpleApp = do
    logText "First simple message"
    logText "Second simple message"

app :: (WithLog env Message m, MonadIO m) => m ()
app = do
    logWarning "Starting application..."
    liftIO $ threadDelay $ 10^(6 :: Int)
    withLog (cmap addApp) $ do
        exceptionL
        logInfo "Application finished..."
  where
    addApp :: Message -> Message
    addApp msg = msg { msgText = "app: " <> msgText msg }



data ExampleException = ExampleException
    deriving stock (Show)
    deriving anyclass (Exception)

exceptionL :: (WithLog env Message m) => m ()
exceptionL = logException ExampleException

----------------------------------------------------------------------------
-- Message passing with pipes: &> and <&

-- Remember:
-- (<&) :: LogAction m msg -> msg -> m ()
----------------------------------------------------------------------------

data Collatz = Collatz {even :: Bool, n :: Int, iteration :: Int}

collatz :: LogAction IO String -> Collatz -> IO ()
collatz logger (Collatz False 1 iter) =
    logger <& ("Found 1 after " ++ show iter ++ " iterations")
collatz logger (Collatz even' x iter) = do
    logger <& (show x ++ " on iteration " ++ show iter)
    let newN = if even' then x `div` 2 else 3 * x + 1
    collatz logger $ Collatz (newN `mod` 2 == 0) newN (iter + 1)

----------------------------------------------------------------------------
-- Section with contravariant combinators example
----------------------------------------------------------------------------

data Engine = Pistons Int | Rocket

engineToEither :: Engine -> Either Int ()
engineToEither e = case e of
    Pistons i -> Left i
    Rocket    -> Right ()

data Car = Car
    { carMake   :: String
    , carModel  :: String
    , carEngine :: Engine
    }

carToTuple :: Car -> (String, (String, Engine))
carToTuple (Car make model engine) = (make, (model, engine))

stringL :: LogAction IO String
stringL = logStringStdout

-- Returns log action that logs given string ignoring its input.
constL :: String -> LogAction IO a
constL s = s >$ stringL

intL :: LogAction IO Int
intL = logPrint

-- log actions that logs single car module
carL :: LogAction IO Car
carL = carToTuple
    >$< (constL "Logging make..." *< stringL >* constL "Finished logging make...")
    >*< (constL "Logging model.." *< stringL >* constL "Finished logging model...")
    >*< ( engineToEither
      >$< constL "Logging pistons..." *< intL
      >|< constL "Logging rocket..."
        )

----------------------------------------------------------------------------
-- Custom monad and logger actions of different types
----------------------------------------------------------------------------

data Env m = Env
    { envLogString :: LogAction m String
    , envLogInt    :: LogAction m Int
    }

instance HasLog (Env m) String m where
    getLogAction :: Env m -> LogAction m String
    getLogAction = envLogString

    setLogAction :: LogAction m String -> Env m -> Env m
    setLogAction newAction env = env { envLogString = newAction }

instance HasLog (Env m) Int m where
    getLogAction :: Env m -> LogAction m Int
    getLogAction = envLogInt

    setLogAction :: LogAction m Int -> Env m -> Env m
    setLogAction newAction env = env { envLogInt = newAction }

newtype FooM a = FooM
    { runFooM :: ReaderT (Env FooM) IO a
    } deriving newtype (Functor, Applicative, Monad, MonadIO, MonadReader (Env FooM))

usingFooM :: Env FooM -> FooM a -> IO a
usingFooM env = flip runReaderT env . runFooM

foo :: (WithLog env String m, WithLog env Int m) => m ()
foo = do
    logMsg ("String message..." :: String)
    logMsg @Int 42

logFoo :: IO ()
logFoo = usingFooM env foo
  where
    env :: Env FooM
    env = Env
        { envLogString = liftLogIO logStringStdout
        , envLogInt    = liftLogIO logPrint
        }

