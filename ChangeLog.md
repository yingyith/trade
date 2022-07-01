# Changelog for trade

add ine
## Unreleased changes
2022-6-30
need to add appand position state to stm object,then can use strategy like rescure stretegy that is try best to find ways to fastest and least profit close order
for example : 
    Now is fall fast,open price is 0.45,side is long,now price is 0.44,so best strategy is wait to find next pos that have up trend,like 0.43,so double the quant,then 
    we can close at (0.45+0.43x2)/3 = 0.4367,we can close at 0.4372.This is save mode. 
    it is triggered when now is strict environment
