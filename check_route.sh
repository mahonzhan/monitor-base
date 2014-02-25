#!/bin/bash
# 2014/02/25 check_route.sh

dir="/usr/local/monitor-base"
function getSubnet() {
    [ $# -ne 1 ] && echo "Usage:`basename $0` <ip> <prefix>" && return 1
    ip=${1%/*}
    prefix=${1#*/}
    ipbin=`printf "%08d" $(echo "obase=2;$(echo $ip | tr '.' ';')" | bc)`
    netbit=${ipbin:0:$prefix}
    hostbit=${ipbin:$prefix}
    # for subnet
    subnetbit=${hostbit//1/0}
    # for broadcast
    broadcastbit=${hostbit//0/1}
    subnet="$netbit$subnetbit"
    broadcast="$netbit$broadcastbit"
    echo "$((2#$ipbin)),$((2#$subnet)),$((2#$broadcast))"
    #masktmp=`printf "%b" $(for((i=0;i<$prefix;i++));do echo -n "1";done)`
    #mask=$(( $((2#$masktmp)) << $((32-$prefix)) ))
    #maskbin=`echo "obase=2;$mask" | bc`
    #subnet=$(( $((2#$ipbin)) & $((2#$maskbin)) ))
    #subnetbin=`echo "obase=2;$subnet" | bc`
    #echo "$subnetbin $broadcast"
}

# if multi route, then get ip rule from subnet
routeTableArray=(`egrep -v '^#|local|main|default|unspec' /etc/iproute2/rt_tables | awk '{print$2}'`)
subnetArray=()
if ! echo "${routeTableArray[@]}" | grep "cnc" >/dev/null && echo "${routeTableArray[@]}" | grep "tel" >/dev/null;then
    echo "No need to check single route"
    exit 0
fi

# check totel or tocnc rule
echo "=== check ip route ==="
dest_tel="202.96.128.86"
dest_cnc="202.96.64.68"
tel_gw=`/sbin/ip route get $dest_tel | awk '/via/{print$3}'`
cnc_gw=`/sbin/ip route get $dest_cnc | awk '/via/{print$3}'`

echo "tel_gw:$tel_gw"
echo "cnc_gw:$cnc_gw"

if [ "$tel_gw" != "$cnc_gw" ]; then
    echo "ip route OK"
else
    echo "ip route error"
    message="$HOSTNAME same tel traceroute:$dest_tel->$tel_gw, cnc traceroute:$dest_cnc->$cnc_gw."
    $dir/bin/alarm.sh "$HOSTNAME route alarm"  "$message" "$HOSTNAME"
    exit 1
fi

echo "=== check ip rule ==="
/sbin/ip rule show | grep -v 'from all' >$dir/log/iprule.log
for routeTable in ${routeTableArray[@]};do
    gw=`/sbin/ip route show table $routeTable | awk '{print$3}'`
    ping -n -c1 -W1 $gw >/dev/null || $dir/bin/alarm.sh "$HOSTNAME gw alarm" "$routeTable's gateway $gw unreachable" "$HOSTNAME"
    subnet=`cat $dir/log/iprule.log | grep "$routeTable" | awk '{print$3}'`
    subnetbin=`getSubnet $subnet`
    subnetArray+=($subnetbin)
done

# get ip address, then check if the ip is in the rule from subnet
for iprefix in `/sbin/ip address | grep inet | egrep 'eth|em' | awk '$2 !~ "^10.|^192.|^172."{print$2}'`;do
    subnetbin=`getSubnet $iprefix`
    ipdec=`echo "$subnetbin" | cut -d, -f1`
    ruleok=''
    for i in ${subnetArray[@]};do
        min=`echo $i | cut -d, -f2`
        max=`echo $i | cut -d, -f3`
        if [ $ipdec -ge $min -a $ipdec -le $max ];then
            ruleok="ip rule ok: $iprefix is in the ip rule from subnet"
            echo "$ruleok"
        fi
    done
    if [ -z "$ruleok" ];then
        ruleerr="ip rule error: $iprefix not in the ip rule from subnet"
        echo "$ruleerr"
        $dir/bin/alarm.sh "$HOSTNAME ip rule alarm"  "$ruleerr" "$HOSTNAME"
    fi
done
