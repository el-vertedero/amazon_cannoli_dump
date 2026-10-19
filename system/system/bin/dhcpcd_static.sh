#!/system/bin/sh

DNS1=`getprop dhcp.wlan0.dns1`
DNS2=`getprop dhcp.wlan0.dns2`
IP=`getprop dhcp.wlan0.ipaddress`
MASK=`getprop dhcp.wlan0.mask`
GW=`getprop dhcp.wlan0.gateway`

exec /system/bin/dhcpcd -S ip_address=$IP -S subnet_mask=$MASK -S routers=$GW -S domain_name_servers="$DNS1 $DNS2" wlan0 -K
