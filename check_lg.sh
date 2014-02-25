#!/bin/bash
# 2014/2/20 check_lg.sh

dir="/usr/local/monitor-base"
[ `arch` == "x86_64" ] && diskutil="/opt/MegaRAID/MegaCli/MegaCli64" || diskutil="/opt/MegaRAID/MegaCli/MegaCli"
[ ! -f $diskutil ] && diskutil="$dir/bin/MegaCli"
df -kP >$dir/log/lg.log
#mnt_dev=(`cat $dir/log/lg.log | awk '/\/dev\/sd|\/dev\/cciss/{print substr($1,0,match($1,"0d|sd")+2)}' | sort | uniq`)
mnt_point=(`awk '{if($1 ~ "dev" && $NF !~ "/boot|/var/log") print$NF}' $dir/log/lg.log`)
ctrlId=`cat $dir/log/check_disk_num.log | awk -F: '/id/ {print$NF}'`
for i in ${mnt_point[@]};do
    spec=''
    # check rw
    touch $i/check_disk.log &>/dev/null || spec='!'  # touch fail
    # check usage
    usage=`cat $dir/log/lg.log | grep -w "$i" | awk '{print substr($5,0,match($5,"%")-1)}'`
    available=`cat $dir/log/lg.log | grep -w "$i" | awk '{print$4}'`
    [ $available -le $((2048*1024)) ] && spec='!'
    # check fs error
    grep -w "$i" $dir/log/fs_kern.log >/dev/null && spec='*'  # fs error    
    # check smart
    mnt_dev=`grep -w "$i" $dir/log/lg.log | awk '{print substr($1,0,match($1,"0d|sd")+3)}'`
    if [[ $ctrlId =~ [0,2,5] ]];then
        /usr/sbin/smartctl -H $mnt_dev >/dev/null
        smartstat=$(($? & 8))
        [ $smartstat -ne 0 ] && spec='-'  # smart fail
    elif [ $ctrlId -eq 1 ];then
        # check write policy
        alpha=`echo $mnt_dev | awk '{print substr($1,match($1,"0d|sd")+2,1)}'`
        ascii=`printf "%d" "'$alpha"`
        ldnum=$(($ascii-97))
        #echo "$alpha $ldnum"
        writePolicy=`$diskutil -LDInfo -L$ldnum -a0 | awk '/Current Cache Policy/{if($4=="WriteBack,"){print"wb"}else{print"wt"}}'`
    fi
    [ -z "$spec" ] && spec=':'
    up_dev=`echo $mnt_dev | awk '{print substr($1,match($1,"0d|sd")+2)}'`
    echo -n "${up_dev}$spec${usage}${writePolicy},"
done
ui=`df -ikP | awk '$1 ~ "dev" {iUSED=substr($5,0,match($5,"%")-1);if(iUSED>95){if($1 ~ "cciss"){DISK=substr($1,match($1,"0d")+2)}else{DISK=substr($1,8)};printf("%s!i%d,",DISK,iUSED)}}'`
echo -n "$ui"
