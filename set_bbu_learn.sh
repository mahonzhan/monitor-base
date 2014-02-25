#!/bin/bash
# 2014/2/24 set_bbu_learn.sh
if ! [[ $(date +%H%M) =~ 010[0-4] ]];then
    echo "Must run in 01:00-01:05"
    exit 1
fi

dir="/usr/local/monitor-base"
[ `arch` == "x86_64" ] && diskutil="/opt/MegaRAID/MegaCli/MegaCli64" || diskutil="/opt/MegaRAID/MegaCli/MegaCli"
[ ! -f $diskutil ] && diskutil="$dir/bin/MegaCli"

$diskutil -AdpBbuCmd -GetBbuProperties -a0 >$dir/log/BbuProperties.log

# nothing to do with transparent mode
mode=`cat $dir/log/BbuProperties.log | awk '/Auto-Learn Mode:/{print$NF}'`
[ "$mode" == "Transparent" ] && echo "No need to do this when the learn mode is transparent" && exit 0

# correct adp time, suppose it is utc+8
adpTime=`$diskutil -AdpGetTime -a0 | awk -F'Date: |Time: ' '/Date|Time/{printf"%s ",$NF}'`
adpSec=`date -d "$adpTime" +%s`
sysSec=`date +%s`
offset=$(($sysSec-$adpSec))
if [ ${offset#-} -gt 60 ];then
	echo "Now correct time ..."
    $diskutil -AdpSetTime $(date +"%Y%m%d %H:%M:%S") -a0
fi

# check next learn time
nextLearnTime=`cat $dir/log/BbuProperties.log | grep 'Next Learn time' | head -n1 | awk '/Next Learn time.*Sec/{printf"%s",$(NF-1)}'`
[ -z "$nextLearnTime" ] && nextLearnTime=`cat $dir/log/BbuProperties.log | grep 'Next Learn time' | head -n1 | awk -F": " '/Next Learn time/{printf"%s",$NF}'`

if [[ "$nextLearnTime" =~ ^[0-9]+$ ]];then
    # old card use timetick since 2000-1-1
    nextLearnSec=$nextLearnTime
    realTime=`date -d "2000-01-01 + $nextLearnSec secs" +"%Y-%m-%d %H:%M:%S"`
else
    # new card use absolute time, timezone is the same as adp time
    nextLearnSec=`date -d "$nextLearnTime" +%s`
    realTime=`date -d@$nextLearnSec +"%Y-%m-%d %H:%M:%S"`
fi

# set next learn start time to low peak period: 01:00-03:00
realSec=`date -d "$realTime" +%s`
#learnDelayInterval=`$diskutil -AdpBbuCmd -GetBbuProperties -a0 | grep 'Learn Delay Interval' | head -n1 | awk -F':'  '{printf"%s",$NF}' | awk '{print$1}'`
#finalSec=$(($realSec+$learnDelayInterval*3600))
finalTime=`date -d@$realSec +'%Y-%m-%d %H:%M:%S'`
echo "nextLearnTime: $finalTime"
daySec=$((($realSec+8*3600)%(24*3600)))
if [ $daySec -gt 3600 -a $daySec -lt 10800 ];then
    echo "nextLearnTime already between 01:00-3:00"
else
    #if [ $daySec -le 7200 ];then
    #    delaySec=$((7200-$daySec)) 
    #else
    #    delaySec=$((24*3600-$daySec+7200))
    #fi
    #delayHour=$(($delaySec/3600))
    #echo "setDelay: $delayHour"
    #echo "learnDelayInterval=${delayHour}" >$dir/log/BbuProperties.conf
    # cannt work for unkown reason
    #$diskutil -AdpBbuCmd -SetBbuProperties -f $dir/log/BbuProperties.conf -a0
    manualLearnDay=`date -d "$finalTime yesterday" +'%Y%m%d'`
    echo "manualLearnDay=$manualLearnDay"
    currentDay=`date +'%Y%m%d'`
    lastLearn=`cat $dir/log/lastLearn.log`
    lastLearn=${lastLearn:=0}
    currentSec=`date +%s`
    if [ $(($currentSec-$lastLearn)) -le $((20*24*3600)) ];then
        echo "Learn Interval cannt less than 20 days"
        exit 1
    fi
    if [ x"$currentDay" == x"$manualLearnDay" ] && [[ $(date +%H) =~ 0[1-2] ]];then
        echo "Start to learn manually"
        echo "$(date +%s)" >$dir/log/lastLearn.log
        $diskutil -AdpBbuCmd -BbuLearn -a0
    else
        echo "Today is not manualLearnDay or not 01:00-03:00"
    fi
fi
