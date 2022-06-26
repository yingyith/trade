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
    minrulethreshold,
    shortminrulethreshold,
    depthrisksheet,
    holdposkey
) where

defintervallist         :: [String]
defintervallist         = ["3m","5m","15m","1h","4h","12h","3d"] 

quanlist                :: [Int]
quanlist                = [300,500,1000,2000,4000,8300] -- 15m,1h,4h,12h

stopprofitlist          :: [Double]
stopprofitlist          = [0.0006,0.001,0.0014,0.0018,0.0022,0.0026] -- 15m,1h,4h,12h

diffspreadsheet         :: [Double]
diffspreadsheet         = [0.2   ,0.33  ,0.58  ,0.72  ,0.8  ,0.88  ,0.95  ,1] 

depthrisksheet          :: [Int] 
depthrisksheet          = [500   ,710   ,910   ,1010  ,1260  ,1410  ,2100 ]   --deothrisksheet x 2  = minrulethreshold + shortminrulethreshold 

minrulethreshold        :: [Int] --base  to serious degree
minrulethreshold        = [2000  ,1600  ,1100  ,700  ]   --   4h, 1h,15m -->    d,d,d  ;u,u,u  -> 2000
                                                                         --     d,d,u  ;u,u,d  -> 1800
                                                                         --     d,u,d  ;u,d,u  -> 1500
                                                                         --     d,u,u  ;u,d,d  -> 700 

shortminrulethreshold   :: [Int] --base  to serious degree
shortminrulethreshold   = [2000  ,1000  ,450  ]   -- turple 5, (a,b,c,d,e)  (a,b) is for quant number  degree ,(c,d,e) for  profit distance
                     -- [a      ,b    ,c     ,d]
                     

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
