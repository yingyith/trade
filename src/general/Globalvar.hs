{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE DeriveAnyClass #-}
-- A test for PubSub which must be run manually to be able to kill and restart the redis-server.
-- I execute this with `stack runghc ManualPubSub.hs`
module Globalvar (
    defintervallist,
    orderkey,
    fivemkey,
    threemkey,
    adakey,
    secondkey,
    usdtkey,
    liskey,
    timekey,
    sellorderid,
    buyorderid,
    secondstick,
    holdprkey,
    minquan,
    quanlist,
    holdposkey
) where

defintervallist :: [String]
defintervallist = ["3m","5m","15m","1h","4h","12h","3d"] 

quanlist :: [Int]
quanlist = [1300,2300,4300,8300,15300] -- 15m,1h,4h,12h

orderkey = "Order"

timekey = "Time"

fivemkey = "5m"
threemkey = "3m"
secondkey = "1s"

adakey = "Ada"
usdtkey = "Usdt"
holdprkey = "Holdpr"
holdposkey = "Holdpos"
liskey = "liskey"
secondstick = 60 :: Integer
sellorderid = "Sellorder20"
buyorderid = "Buyyorder20"
minquan = 200 
