{-# LANGUAGE DeriveGeneric #-}
module Lib
    ( someFunc,
      Person,
      Persons
    ) where
import GHC.Generics
import Data.Aeson
import Data.Text
data Person = Person {
      name :: Text
    , age  :: Int
    } deriving (Generic, Show)

data Persons = Persons {
      persons :: [Person]
    } deriving (Generic, Show)

instance ToJSON Person
instance FromJSON Person

instance ToJSON Persons
instance FromJSON Persons

someFunc :: IO ()
someFunc = putStrLn "someFunc"
