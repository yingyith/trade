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
    stopprofitlist,
    depthkey,
    biddepth,
    askdepth,
    diffspreadsheet,
    depthrisksheet,
    holdposkey
) where

defintervallist :: [String]
defintervallist = ["3m","5m","15m","1h","4h","12h","3d"] 

quanlist :: [Int]
quanlist = [300,500,1000,2000,4000,8300] -- 15m,1h,4h,12h

stopprofitlist :: [Double]
stopprofitlist = [0.0006,0.001,0.0014,0.0018,0.0022,0.0026] -- 15m,1h,4h,12h

diffspreadsheet :: [Double]
diffspreadsheet = [0.06 ,0.1  ,0.2  ,0.4  ,0.8  ,1.2  ,1.6  ,2] 

depthrisksheet :: [Int] 
depthrisksheet = [100  ,120  ,160 , 200 , 300, 400 , 520  ]   -- 

biddepth = "Biddepth"
askdepth = "Askdepth"

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
depthkey = "depthkey"
secondstick = 60 :: Integer
sellorderid = "1sCrw2kRUAF9CvJDGK16IP"
buyorderid = "1bCrw2kRUAF9CvJDGK16IP"
minquan = 200 
