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
    adjustratiosheet,
    adjustboostgrid,
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
diffspreadsheet         = [0.18   ,0.3   ,0.46  ,0.65  ,0.75  ,0.81  ,0.88  ,0.95  ,1] 

depthrisksheet          :: [Int] 
depthrisksheet          = [-1000  ,450   ,710   ,1510   ,1710  ,1860  ,2050  ,2300 ]   --deothrisksheet x 2  = minrulethreshold + shortminrulethreshold 

minrulethreshold        :: [Int] --base  to serious degree
minrulethreshold        = [2000  ,1600  ,1100  ,900  ]   --   4h, 1h,15m -->    d,d,d  ;u,u,u  -> 2000
                                                                         --     d,d,u  ;u,u,d  -> 1800
                                                                         --     d,u,d  ;u,d,u  -> 1500
                                                                         --     d,u,u  ;u,d,d  -> 700 

shortminrulethreshold   :: [Int] --base  to serious degree
shortminrulethreshold   = [2000  ,1200  ,550  ]   -- turple 5, (a,b,c,d,e)  (a,b) is for quant number  degree ,(c,d,e) for  profit distance
                     
adjustratiosheet :: [Double]
adjustratiosheet = [0.001   , 0.15        , 0.25        ,  0.35      , 0.5          , 0.76        , 0.9                , 1     ]

adjustboostgrid :: [(Int,Int)]
adjustboostgrid =  [(0,300) ,(100,500)   ,(200,800)   , (400,1000), (1800,2500)  ,(2500,4000) , (4000,5000)               ]

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
