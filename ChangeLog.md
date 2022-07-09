# Changelog for trade

add ine
## Unreleased changes
2022-6-30
need to add appand position state to stm object,then can use strategy like rescure stretegy that is try best to find ways to fastest and least profit close order
for example : 
    Now is fall fast,open price is 0.45,side is long,now price is 0.44,so best strategy is wait to find next pos that have up trend,like 0.43,so double the quant,then 
    we can close at (0.45+0.43x2)/3 = 0.4367,we can close at 0.4372.This is save mode. 
    it is triggered when now is strict environment

2022-7-09
need to add ccc factor which is affect by (affect price diff and support period),min_rule and sndrule return type should add them.
when an order is stucked ,then use ccc factor to double it and the same time to broaden its profit span.
for example :
    An Order stuck at (0.4566,"up",hlspread,motivate type ), if motivate type is weak support (only aaa and bbb),then add position distance is long ,(accroding hlspread) 
                                                             if motivate type is strong support (have ccc),then add position change is supported by next grid ccc(support)

