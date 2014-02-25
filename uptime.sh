#!/bin/bash
# 2014/2/20 uptime.sh

if [ $# -ne 1 ] ; then
    echo "usage: $0 <host>"
    exit 1
fi

dir="/usr/local/monitor-base"
nu="/dev/null"
out="$dir/conf/on.cmd"

center=`$dir/bin/getcmd.sh center 1`
if [ "$center" == "" ]
then
    exit 1
fi

host=$1
sz=`$dir/bin/getflowload 10`
echo "" > $out

#########################################################
# packets error drop overrun, 20130625
packlog="$dir/log/pack.log"

function get_stat() {
    rx_info=`/sbin/ifconfig $1 | grep "RX packets"`
    tx_info=`/sbin/ifconfig $1 | grep "TX packets"`
    rx_err=`echo $rx_info | awk '{print$3}' | cut -d':' -f2`
    rx_drop=`echo $rx_info | awk '{print$4}' | cut -d':' -f2`
    rx_over=`echo $rx_info | awk '{print$5}' | cut -d':' -f2`
    tx_err=`echo $tx_info | awk '{print$3}' | cut -d':' -f2`
    tx_drop=`echo $tx_info | awk '{print$4}' | cut -d':' -f2`
    tx_over=`echo $tx_info | awk '{print$5}' | cut -d':' -f2`
}

if [ ! -f $packlog ];then
    /sbin/ifconfig | grep -wE 'eth[0-9] |em[1-9] ' | cut -d' ' -f1 | while read int;do
        get_stat $int
        echo "$int $rx_err $rx_drop $rx_over $tx_err $tx_drop $tx_over" >> $packlog
    done

else
    while read int old_rx_err old_rx_drop old_rx_over old_tx_err old_tx_drop old_tx_over;do
        get_stat $int
        rx_err_inc=$(($rx_err-$old_rx_err))
        rx_drop_inc=$(($rx_drop-$old_rx_drop))
        rx_over_inc=$(($rx_over-$old_rx_over))
        tx_err_inc=$(($tx_err-$old_tx_err))
        tx_drop_inc=$(($tx_drop-$old_tx_drop))
        tx_over_inc=$(($tx_over-$old_tx_over))
        pack="$pack$int:r:${rx_err_inc},${rx_drop_inc},${rx_over_inc},t:${tx_err_inc},${tx_drop_inc},${tx_over_inc};"
        sed -i "/$int/c$int $rx_err $rx_drop $rx_over $tx_err $tx_drop $tx_over" $packlog
    done < $packlog
fi

#########################################################
# serial, 20130821
seri=`/usr/sbin/dmidecode --type 1, 27 | grep "Serial Number" | awk '{print $3}'`
# memory size(with esx support), 20130820
ostype=`uname -r | grep ESX >/dev/null && echo esx || echo linux`
mem=`[ "$ostype" == "esx" ] && /usr/sbin/esxcfg-info -w | grep "Physical Memory" | awk -F[.\ ] '{print $(NF-1)}' || free | awk '/Mem/{print$2}'`

#########################################################
## disk num and size check, 20130822
disklog="$dir/log/check_disk_num.log"
disknum="$dir/bin/check_disk/check_disk_num.fix"
fhour=`date +%H`
# first disklog
if ! grep "id" $disklog;then  
    echo "FLAG-HOUR:$fhour" > $disklog
    $dir/bin/check_disk/check_phy_disk.sh >> $disklog
fi
# first disknum
[ ! -f $disknum ] && cat $disklog | egrep -v 'ctrl|FLAG-HOUR|critical_num' | wc -l >$disknum
# check disk per hour
if [ "FLAG-HOUR:$fhour" != "`cat $disklog | grep FLAG-HOUR`" ];then
    echo "FLAG-HOUR:$fhour" > $disklog
    $dir/bin/check_disk/check_phy_disk.sh >> $disklog
fi
# detect disk num change
cur_num=`cat $disklog | egrep -v 'Failed|ctrl|FLAG-HOUR|critical_num' | wc -l`
old_num=`cat $disknum`
critical_num=`awk -F: '/critical_num/{print$2}' $disklog`
critical_num=${critical_num:=0}
[ $cur_num -ne $old_num -o $critical_num -ne 0 ] && failed="!" || failed="="
ph=`echo -n $failed;cat $disklog | egrep -v 'ctrl|FLAG-HOUR|critical_num' | awk '{print$NF}' | sort | uniq -c | sed -r -e 's/\s+//' -e 's/\s+/\*/' | tr '\n' '+' | sed 's/+$//'`
raid=`cat $disklog | awk -F: '/id/ {print$NF}'`

#########################################################
# check logical disk
lg=`$dir/bin/check_lg.sh`
bbu=`$dir/bin/check_bbu.sh`

#########################################################
param="host=$host&seri=$seri&$sz&pack=$pack&mem=$mem&raid=$raid&ph$ph&lg=$lg&$bbu"

if [ "$center" == "on.cc.sandai.net" ]
then
    wget -o $nu -O $out "http://on.cc.sandai.net/ontime/on_time?$param"
else
    
    wget -e httpproxy=$center -o $nu -O $out "http://on.cc.sandai.net/ontime/on_time?$param"
fi

# time alarm, 20130529
local_time=`stat $dir/conf/on.cmd -c %Z`
center_time=`cat $dir/conf/on.cmd | grep OK | awk '{print$3}'`
offset=`expr ${local_time} - ${center_time}`
[ `cat $dir/conf/on.cmd | grep OK | awk '{print NF}'` -eq 3 ] && [ ${offset#-} -ge 60 ] && $dir/bin/alarm.sh "$host time alarm" "time offset = ${offset} seconds" $host

command()
{
    sz=`echo "$1" | grep conf| wc -l`
    if [ $sz -lt 1 ]
    then
        return
    fi

    if [ ! -f $dir/conf/on.conf ]
    then
        echo "$1" > $dir/conf/on.conf
        return
    fi

    sz=`echo "$1" | awk '{print$2}'`
    old=`cat $dir/conf/on.conf | grep "$sz" | wc -l`
    if [ $old -gt 0 ]
    then
        sed -i "/$sz/d" $dir/conf/on.conf
    fi
    echo "$1" >> $dir/conf/on.conf
    return
}

while read LINE
do
    command "$LINE"
done < $out

$dir/bin/set_bbu_learn.sh
