#!/system/bin/sh
# Android system properties that are required by OOBE are set here.
setprop p2p.server.addr 10.201.126.241
setprop p2p.server.prefixLength 28
setprop p2p.server.dhcpRange 10.201.126.242,10.201.126.254,20m
setprop lab126.p2p.companion.app.ip 10.201.126.242/24
setprop com.lab126.dnsmasq_script /system/bin/p2p_dnsmasq.sh

