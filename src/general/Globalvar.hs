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
    minrulesheet,
    depthrisksheet,
    holdposkey
) where

defintervallist   :: [String]
defintervallist   = ["3m","5m","15m","1h","4h","12h","3d"] 

quanlist          :: [Int]
quanlist          = [300,500,1000,2000,4000,8300] -- 15m,1h,4h,12h

stopprofitlist    :: [Double]
stopprofitlist    = [0.0006,0.001,0.0014,0.0018,0.0022,0.0026] -- 15m,1h,4h,12h

diffspreadsheet   :: [Double]
diffspreadsheet   = [0.2 ,0.54  ,0.73  ,0.86  ,0.92  ,0.96  ,0.98  ,1] 

depthrisksheet    :: [Int] 
depthrisksheet    = [110  ,210  ,410 , 510 , 610, 710 , 810 ]   -- 

minrulesheet      :: [Int] --base  to serious degree
minrulesheet      = [ -1100 ,-700  ,-600 , -700  ]   -- 

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
sellorderid = "yid1sCrw2kRUAF9CvJDGK16IP"
buyorderid = "yid1bCrw2kRUAF9CvJDGK16IP"
minquan = 200  :: Int
