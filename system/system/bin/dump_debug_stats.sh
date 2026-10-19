# dump_debug_stats.sh
#
# Dumping all debugging related statistics.
# It needs an interface name (eth0 or br0) as an argument
# to call it.
#
#!/system/bin/sh

# mesh debugging

curr_time=`date +%Y-%m-%d' '%H:%M:%S`
echo $curr_time "Started dumping mesh debug status/stats"

TYPE=$1
CONF_PATH=$2

print_host_info() {
    ifconfig br0
    echo "";
    cat /proc/net/arp
    echo "";
}

print_bridge_info() {
    bridge link show
    echo ""
}

print_radio_info() {
    iw.1 dev
    echo ""
}

print_mesh_info() {
    iw.1 dev mesh0 station dump
    echo ""
    iw.1 dev mesh0 mpath dump mbss0
    echo ""
}

print_conf_info() {
    if [ -n "$CONF_PATH" ]; then
        cat $CONF_PATH"/mesh_supplicant.conf"
        echo ""
        cat $CONF_PATH"/hostapd.conf"
        echo ""
    else
        echo "Wrong folder PATH of conf"
    fi
}

if [ "$TYPE" == "ALL" ] || [ "$TYPE" == "HOST" ]; then
    echo "### Print host interface information ###"
    print_host_info
fi

if [ "$TYPE" == "ALL" ] || [ "$TYPE" == "RADIO" ]; then
    echo "### Print radio information ###"
    print_radio_info
fi

if [ "$TYPE" == "ALL" ] || [ "$TYPE" == "BRIDGE" ]; then
    echo "### Print bridge information ###"
    print_bridge_info
fi

if [ "$TYPE" == "ALL" ] || [ "$TYPE" == "MESH" ]; then
    echo "### Print mesh information ###"
    print_mesh_info
fi

if [ "$TYPE" == "ALL" ] || [ "$TYPE" == "CONF" ]; then
    echo "### Print wpa_supplicant/hostapd conf ###"
    print_conf_info
fi