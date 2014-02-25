#!/bin/bash
# 2014/2/18 check_bbu.sh

dir="/usr/local/monitor-base"
ctrlId=`cat $dir/log/check_disk_num.log | awk -F: '/id/ {print$NF}'`
if [ $ctrlId -eq 1 ];then
    [ `arch` == "x86_64" ] && diskutil="/opt/MegaRAID/MegaCli/MegaCli64" || diskutil="/opt/MegaRAID/MegaCli/MegaCli"
    [ ! -f $diskutil ] && diskutil="$dir/bin/MegaCli"
    
    isgood=`$diskutil -AdpBbuCmd -GetBbuStatus –a0 | awk '/isSOHGood/{print$2}'`
    [ x"$isgood" == x"Yes" ] && spec="=" || spec="!"
    percent=`$diskutil -AdpBbuCmd -GetBbuStatus –a0 | grep 'Relative State of Charge' | awk '{print$(NF-1)}'`
    memory=`$diskutil -CfgDsply -a0 | awk '/Memory/{print$2}'`
    echo -n "B$spec$percent,$memory"
fi
