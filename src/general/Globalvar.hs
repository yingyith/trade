{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`
module Globalvar (
    defintervallist,
    orderkey,
    fivemkey,
    adakey,
    usdtkey
) where

defintervallist :: [String]
defintervallist = ["1m","5m","15m","1h","4h","12h","3d"] 

orderkey = "Order"

fivemkey = "5m"

adakey = "Ada"
usdtkey = "Usdt"
