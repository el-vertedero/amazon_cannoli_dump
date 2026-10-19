#!/system/bin/sh
#
# Copyright (c) 2020 - 2026 Amazon.com, Inc. or its affiliates.  All rights reserved.
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#

DNSMASQ_DATA_PATH=/data/misc/dhcp/
IPTABLES=/system/bin/iptables
IP6TABLES=/system/bin/ip6tables
DEBUG_RULES_HOOK=/system/bin/debug_firewall.sh
GREENGRASS_RULES_HOOK=/system/bin/greengrass_firewall.sh
OTBR_BIN=/system/bin/otbr-agent
GETPROP=/system/bin/getprop
LOG=/system/bin/log
TAG=Firewall
OOBEIP=$($GETPROP p2p.server.addr)
GET_DYN_CONF=/system/bin/get-dynconf-value
COMPANION_APP_TCPTUNNEL_PORT_CONF_NAME=url.companionapp.tcptunnel.port
COMPANION_APP_TCPTUNNEL_PORT=$($GETPROP persist.oobe.compapp.port)
WPA_CLI=/system/bin/wpa_cli
DNS1IP=$($GETPROP net.dns1)
DNS2IP=$($GETPROP net.dns2)
DNS4IP=$($GETPROP net.dns4)
DNS5IP=$($GETPROP net.dns5)
TCPTUNNEL_LOCAL_LISTENING_PORT=$($GETPROP lab126.oobe.local.listening.prt)

# Read the P2P interface name
target=$($GETPROP ro.product.name)
if [ "${target}" == "radar_puffin" ] || [ "${target}" == "biscuit_puffin" ]; then
    P2PIF=p2p0
else
    IF_NAME='p2p-p2p0-'
    P2PIF=$($WPA_CLI interface | grep $IF_NAME)
fi

print() {
    $LOG -t $TAG $1
}

# If '.' in the address, then it's IPv4.
# The iput comes from properties, should be valid V4 or V6 address
function valid_ipv4() {
    local  ip=$1
    local  stat=1

    OIFS=$IFS
    IFS='.'
    tokens=($ip)
    IFS=$OIFS

    [[ ${#tokens[@]} -gt 1 ]]
    stat=$?
    return $stat
}

get_companion_app_tcptunnel_port() {

    # set the local variable port to ""
    local port=""
    if [ -e ${GET_DYN_CONF} ]; then
        port=$(${GET_DYN_CONF} ${COMPANION_APP_TCPTUNNEL_PORT_CONF_NAME})
    fi

    if [ "${port}" == "" ]; then
        port=${COMPANION_APP_TCPTUNNEL_PORT}
    fi

    print "Companion App TCPTunnel Port:${port}"
    echo -n "${port}"
}

if [ ! -x $IPTABLES ]; then
    print "$IPTABLES... not found"
    exit 1
fi

set_default_rules_for_interface() {
    local interface=$1

    if [ -z $interface ]; then
        print "interface is empty"
        return
    fi

    print "Setting up default firewall rules for interface $interface"

    # Accept RELATED,ESTABLISHED connections on interface (device initiated)
    $IPTABLES -A INPUT -i $interface -p tcp -m state --state RELATED,ESTABLISHED -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p udp -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Spotify Connect login server.
    $IPTABLES -A INPUT -i $interface -p tcp -m tcp --dport 4070 -j ACCEPT

    # Whatify Spotify Connect login server.
    $IPTABLES -A INPUT -i $interface -p tcp -m tcp --dport 4071 -j ACCEPT

    # SIP Calling support
    $IPTABLES -A INPUT -i $interface -p udp --dport 16384:32767 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p tcp --dport 16384:32767 -j ACCEPT

    # TPH traffic on interface. TPH/phd listens on port 40317
    $IPTABLES -A INPUT -i $interface -p tcp -m tcp --dport 40317 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p udp --dport 40317 --sport 40317 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p udp --dport 40317 --sport 49317 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p udp --dport 40317 --sport 33434 -j ACCEPT

    # Whole Home Audio traffic on interface.  The whad listens on:
    # udp port 55442 for audio distribution
    # tcp port 55442 for audio distribution
    # tcp port 55443 for control plane behavior,
    # udp port 55445 for Quantum UDP WHASP
    # tcp port 55445 for TCP WHASP
    # udp port 55446 for multi-tier timestamp exchange
    $IPTABLES -A INPUT -i $interface -p udp --dport 55442 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p tcp -m tcp --dport 55442:55443 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p udp --dport 55444:55446 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p tcp -m tcp --dport 55445 -j ACCEPT

    # Allowlist FFReg http server on port 6543
    $IPTABLES -A INPUT -i $interface -p tcp -m tcp --dport 6543 -j ACCEPT

    # CMB. Allow packets on port 5000
    $IPTABLES -A INPUT -i $interface -p udp --dport 5000 -j ACCEPT

    # Matter use
    $IPTABLES -A INPUT -i $interface -p udp --dport 5540 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p udp --dport 5541 -j ACCEPT
    $IPTABLES -A FORWARD -i $interface -p udp --dport 5540 -j ACCEPT
    $IPTABLES -A FORWARD -i $interface -p udp --dport 5541 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p tcp --dport 5540 -j ACCEPT
    $IPTABLES -A INPUT -i $interface -p tcp --dport 5541 -j ACCEPT
    $IPTABLES -A FORWARD -i $interface -p tcp --dport 5540 -j ACCEPT
    $IPTABLES -A FORWARD -i $interface -p tcp --dport 5541 -j ACCEPT

    # UPnP:
    # Allow traffic on Dst Port 1900 which are UPnP advertisements and Bye Bye
    # Allow traffic on Dst Port 50000 and 50001 which is used in SmartHome Wifi Adapter
    # and LocalMediator respectively as source port.
    $IPTABLES -A INPUT -i $interface  -p udp --dport 1900 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp --dport 50000 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp --dport 50001 -j ACCEPT

    # mDNS: Avahi Publish of Spotify Connect service.
    $IPTABLES -A INPUT -i $interface  -p udp --dport 5353 -j ACCEPT

    # Allow all outgoing traffic on interface
    $IPTABLES -A OUTPUT -o $interface -j ACCEPT

    # Allow LocalAdapterPlatform to listen to UDP Broadcast discovery from Tuya
    $IPTABLES -A INPUT -i $interface -p udp --dport 6667 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    # Allows LocalAdapterPlatform to perform UDP/SSDP Broadcast discovery for LifX, TPLink, Yeelight
    # Allows traffic only from RFC 1918 IP Addresses, ie IP-endoints on local network
    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 50020:50040 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 50020:50040 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 50020:50040 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    # Allows Local Integrations Adapter to perform UDP broadcast discovery / control for Wiz, Govee Magic Home
    # Wiz
    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 38899 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 38899 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 38899 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 38900 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 38900 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 38900 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    # Govee
    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 4001 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 4001 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 4001 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 4002 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 4002 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 4002 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 4003 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 4003 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 4003 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    # Magic Home
    $IPTABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 48899 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 48899 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IPTABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 48899 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
}

# Add default firewall settings here
default_firewall_setup () {
    print "Setting up default firewall settings"
    $IPTABLES --flush

    # Default policy for all chains: DROP
    $IPTABLES -P INPUT DROP
    $IPTABLES -P OUTPUT DROP
    $IPTABLES -P FORWARD DROP

    set_default_rules_for_interface wlan0
    set_default_rules_for_interface eth0
    set_default_rules_for_interface br0

    # ICMP. Allow only responses to local connections
    $IPTABLES -A INPUT -p icmp -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Accept all on the loopback interface
    $IPTABLES -A INPUT -i lo -j ACCEPT
    $IPTABLES -A OUTPUT -o lo -j ACCEPT

    # Add rules for Thread NAT64 and DNS64
    # Thread protocol is a IPv6. To enable thread accessories to connect to IPv4
    # servers, we need to enable NAT64 which requires IPv4 forward for ot0.
    $IPTABLES -I FORWARD -i ot0 -j ACCEPT
    $IPTABLES -I FORWARD -o ot0 -j ACCEPT
    $IPTABLES -I INPUT -i ot0 -j ACCEPT
    $IPTABLES -I OUTPUT -o ot0 -j ACCEPT
    # The thread border router don't advertise an IPv4 address.
    # For NAT64/DNS64 we need to mark and apply NAT masquerading to IPv4 Thread
    # packets.
    $IPTABLES -t mangle -I PREROUTING -i ot0 -j MARK --set-mark 0x1001
    $IPTABLES -t nat -I POSTROUTING -m mark --mark 0x1001 -j MASQUERADE

    # Add rules for internal debugging use
    if [ -f $DEBUG_RULES_HOOK ]; then
        /system/bin/sh $DEBUG_RULES_HOOK
    else
        print "$DEBUG_RULES_HOOK does not exist"
    fi

    if [ -f $GREENGRASS_RULES_HOOK ]; then
        /system/bin/sh $GREENGRASS_RULES_HOOK
    fi

    # Check if adb is enabled before allowing traffic on tcp port 5555
    local usb_prop=$(getprop persist.sys.usb.config)
    if [[ $usb_prop == *adb* ]]; then
        print "Allow ADB over Wifi traffic on tcp port 5555"
        $IPTABLES -A INPUT -p tcp --dport 5555 -j ACCEPT
        $IPTABLES -A OUTPUT -p tcp --sport 5555 -j ACCEPT
    fi
}

set_default_ipv6_rules_for_interface() {
    local interface=$1

    if [ -z $interface ]; then
        print "interface is empty"
        return
    fi

    print "Setting up default firewall rules for interface $interface"

    # Accept RELATED,ESTABLISHED connections on interface (device initiated)
    $IP6TABLES -A INPUT -i $interface -p tcp -m state --state RELATED,ESTABLISHED -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p udp -m state --state RELATED,ESTABLISHED -j ACCEPT

    # Spotify Connect login server.
    $IP6TABLES -A INPUT -i $interface -p tcp -m tcp --dport 4070 -j ACCEPT

    # Whatify Spotify Connect login server.
    $IP6TABLES -A INPUT -i $interface -p tcp -m tcp --dport 4071 -j ACCEPT

    # SIP Calling support
    $IP6TABLES -A INPUT -i $interface -p udp --dport 16384:32767 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p tcp --dport 16384:32767 -j ACCEPT

    # TPH traffic on interface. TPH/phd listens on port 40317
    $IP6TABLES -A INPUT -i $interface -p tcp -m tcp --dport 40317 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p udp --dport 40317 --sport 40317 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p udp --dport 40317 --sport 49317 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p udp --dport 40317 --sport 33434 -j ACCEPT

    # Whole Home Audio traffic on interface.  The whad listens on:
    # udp port 55442 for audio distribution
    # tcp port 55442 for audio distribution
    # tcp port 55443 for control plane behavior,
    # udp port 55445 for Quantum UDP WHASP
    # tcp port 55445 for TCP WHASP
    # udp port 55446 for multi-tier timestamp exchange
    $IP6TABLES -A INPUT -i $interface -p udp --dport 55442 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p tcp -m tcp --dport 55442:55443 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p udp --dport 55444:55446 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p tcp -m tcp --dport 55445 -j ACCEPT

    # Allowlist FFReg http server on port 6543
    $IP6TABLES -A INPUT -i $interface -p tcp -m tcp --dport 6543 -j ACCEPT

    # CMB. Allow packets on port 5000
    $IP6TABLES -A INPUT -i $interface -p udp --dport 5000 -j ACCEPT

    # Casting and User Directed Commissioning support for Matter
    $IP6TABLES -A INPUT -i $interface -p udp --dport 5550 -j ACCEPT

    # Matter use
    $IP6TABLES -A INPUT -i $interface -p udp --dport 5540 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p udp --dport 5541 -j ACCEPT
    $IP6TABLES -A FORWARD -i $interface -p udp --dport 5540 -j ACCEPT
    $IP6TABLES -A FORWARD -i $interface -p udp --dport 5541 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p tcp --dport 5540 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface -p tcp --dport 5541 -j ACCEPT
    $IP6TABLES -A FORWARD -i $interface -p tcp --dport 5540 -j ACCEPT
    $IP6TABLES -A FORWARD -i $interface -p tcp --dport 5541 -j ACCEPT

    # UPnP:
    # Allow traffic on Dst Port 1900 which are UPnP advertisements and Bye Bye
    # Allow traffic on Dst Port 50000 and 50001 which is used in SmartHome Wifi Adapter
    # and LocalMediator respectively as source port.
    $IP6TABLES -A INPUT -i $interface  -p udp --dport 1900 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface  -p udp --dport 50000 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface  -p udp --dport 50001 -j ACCEPT

    # mDNS: Avahi Publish of Spotify Connect service.
    $IP6TABLES -A INPUT -i $interface  -p udp --dport 5353 -j ACCEPT

    # DHCPv6 client port
    $IP6TABLES -A INPUT -i $interface  -p udp --dport 546 -j ACCEPT

    # Allow all outgoing traffic on interface
    $IP6TABLES -A OUTPUT -o $interface -j ACCEPT

    # Allow LocalAdapterPlatform to listen to UDP Broadcast discovery from Tuya
    $IP6TABLES -A INPUT -i $interface -p udp --dport 6667 -m limit --limit 10/s --limit-burst 200 -j ACCEPT

    # Allows LocalAdapterPlatform to perform UDP/SSDP Broadcast discovery for LifX, TPLink, Yeelight
    # Allows traffic only from RFC 1918 IP Addresses, ie IP-endoints on local network
    $IP6TABLES -A INPUT -i $interface  -p udp -s 10.0.0.0/8 --dport 50020:50040 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface  -p udp -s 172.16.0.0/12 --dport 50020:50040 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
    $IP6TABLES -A INPUT -i $interface  -p udp -s 192.168.0.0/16 --dport 50020:50040 -m limit --limit 10/s --limit-burst 200 -j ACCEPT
}

# Add default firewall settings here
default_ipv6_firewall_setup () {
    print "Setting up default ipv6 firewall settings"
    $IP6TABLES --flush

    # Default policy for all chains: DROP
    $IP6TABLES -P INPUT DROP
    $IP6TABLES -P OUTPUT DROP
    $IP6TABLES -P FORWARD DROP

    set_default_ipv6_rules_for_interface wlan0
    set_default_ipv6_rules_for_interface eth0
    set_default_ipv6_rules_for_interface br0

    # Allow all ICMPv6 packets
    $IP6TABLES -A INPUT -p icmpv6 -j ACCEPT
    $IP6TABLES -A OUTPUT -p icmpv6 -j ACCEPT

    # Accept all on the loopback interface
    $IP6TABLES -A INPUT -i lo -j ACCEPT
    $IP6TABLES -A OUTPUT -o lo -j ACCEPT

    #overwrite default policy for thread interface
    $IP6TABLES -A INPUT -i ot0 -j ACCEPT
    $IP6TABLES -A OUTPUT -o ot0 -j ACCEPT
    $IP6TABLES -A FORWARD -i ot0 -j ACCEPT
    $IP6TABLES -A FORWARD -o ot0 -j ACCEPT
}

# Add Alexa hybrid firewall settings for target interface
alexa_hybrid_firewall_interface() {
    local AHE_SECURE_PORT=$1
    print "Setting up alexa hybrid firewall settings for wlan0 and port $AHE_SECURE_PORT"

    if [ -z $AHE_SECURE_PORT ]; then
        print "Invalid parameters. port=$AHE_SECURE_PORT"
        exit 1
    fi

    # Allow extensions device connecting to AHE on given interface
    $IPTABLES -A INPUT -i wlan0 -p tcp --dport $AHE_SECURE_PORT -j ACCEPT
    $IPTABLES -A INPUT -i br0 -p tcp --dport $AHE_SECURE_PORT -j ACCEPT
}

alexa_hybrid_firewall_common() {
    AHE_CLIENT_UID=$1
    AHE_SERVICE_UID=$2
    AHE_PORT=$3

    if [ -z $AHE_CLIENT_UID ] || [ -z $AHE_SERVICE_UID ] || [ -z $AHE_PORT ]; then
        print "Invalid parameters. client=$AHE_CLIENT_UID, service=$AHE_SERVICE_UID, port=$AHE_PORT"
        exit 1
    fi

    # Create new chain ahe_out if not exist
    $IPTABLES -N ahe_out >> /dev/null 2>&1
    # Filter OUTPUT through ahe_out
    $IPTABLES -I OUTPUT 1 -j ahe_out
    # Remove any existing rules on the ahe_out chain
    $IPTABLES --flush ahe_out
    # Drop traffic from a non alexa hybrid client user to AHE port/prevent impersonating PuffinApp process.
    # Accept packets for an ESTABLISHED connection. This is required to allow FIN packets.
    $IPTABLES -A ahe_out -o lo -p tcp --dport $AHE_PORT -d 127.0.0.1 -m state --state ESTABLISHED -j ACCEPT
    $IPTABLES -A ahe_out -o lo -p tcp --dport $AHE_PORT -d 127.0.0.1 -m owner ! --uid-owner $AHE_CLIENT_UID -j DROP
    # Drop traffic from a non alexa hybrid service user from AHE port/prevent impersonating AHE process.
    # Don't accept for ESTABLISHED connection. When client initiates connection the SYN_ACK packet is
    # considered as part of ESTABLISHED connection. We don't want that.
    # We want to include SYN_ACK packets in owner uid filter.
    $IPTABLES -A ahe_out -o lo -p tcp --sport $AHE_PORT -s 127.0.0.1 -m owner ! --uid-owner $AHE_SERVICE_UID -j DROP
}

alexa_hybrid_firewall_setup () {
    print "alexa_hybrid_firewall_setup"
    local AHE_CLIENT_UID='puffin'
    local AHE_SERVICE_UID='ahe'
    local AHE_PORT=7802
    local AHE_SECURE_PORT=7805
    alexa_hybrid_firewall_interface ${AHE_SECURE_PORT}
    alexa_hybrid_firewall_common ${AHE_CLIENT_UID} ${AHE_SERVICE_UID} ${AHE_PORT}
}

# Add AICF messenger firewall settings for target interface
aicf_messenger_firewall_interface() {
    local INTERFACE=$1
    local AICF_MESSENGER_SECURE_PORT=$2
    local AICF_MESSENGER_RESERVE_START=$3
    local AICF_MESSENGER_RESERVE_END=$4

    print "Setting up AICF messenger firewall settings for $INTERFACE and port $AICF_MESSENGER_SECURE_PORT"

    if [ -z $AICF_MESSENGER_SECURE_PORT ]; then
        print "Invalid parameters. port=$AICF_MESSENGER_SECURE_PORT"
        exit 1
    fi

    # Allow remote AicfMessenger to connect to AicfMessenger on the device on given interface
    $IPTABLES -A INPUT -i $INTERFACE -p tcp --dport $AICF_MESSENGER_SECURE_PORT -j ACCEPT

    # Reserve ports for future control plane use.  Block all traffic for now
    if [ ! -z $AICF_MESSENGER_RESERVE_START -a ! -z $AICF_MESSENGER_RESERVE_END ]; then
        $IPTABLES -A INPUT -i $INTERFACE -p tcp --dport $AICF_MESSENGER_RESERVE_START:$AICF_MESSENGER_RESERVE_END -j DROP
        $IPTABLES -A OUTPUT -o $INTERFACE -p tcp --dport $AICF_MESSENGER_RESERVE_START:$AICF_MESSENGER_RESERVE_END -j DROP
    fi
}

aicf_messenger_firewall_common() {
    AICF_MESSENGER_CLIENT_UID=$1
    AICF_MESSENGER_SERVICE_UID=$2
    AICF_MESSENGER_PORT=$3

    if [ -z "$AICF_MESSENGER_CLIENT_UID" ] || [ -z "$AICF_MESSENGER_SERVICE_UID" ] || [ -z "$AICF_MESSENGER_PORT" ]; then
        print "Invalid parameters. client=$AICF_MESSENGER_CLIENT_UID, service=$AICF_MESSENGER_SERVICE_UID, port=$AICF_MESSENGER_PORT"
        exit 1
    fi

    # Create new chain aicfmessenger_out if not exist
    $IPTABLES -N aicfmessenger_out >> /dev/null 2>&1
    # Filter OUTPUT through aicfmessenger_out
    $IPTABLES -I OUTPUT 1 -j aicfmessenger_out
    # Remove any existing rules on the aicfmessenger_out chain
    $IPTABLES --flush aicfmessenger_out
    # Drop traffic from a non aicf messenger client user to AICF messenger port/prevent impersonating PuffinApp process.
    # Accept packets for an ESTABLISHED connection. This is required to allow FIN packets.
    $IPTABLES -A aicfmessenger_out -o lo -p tcp --dport $AICF_MESSENGER_PORT -d 127.0.0.1 -m state --state ESTABLISHED -j ACCEPT
    $IPTABLES -A aicfmessenger_out -o lo -p tcp --dport $AICF_MESSENGER_PORT -d 127.0.0.1 -m owner ! --uid-owner $AICF_MESSENGER_CLIENT_UID -j DROP
    # Drop traffic from a non aicf messenger user from AICF messenger port/prevent impersonating AicfMessenger.
    # Don't accept for ESTABLISHED connection. When client initiates connection the SYN_ACK packet is
    # considered as part of ESTABLISHED connection. We don't want that.
    # We want to include SYN_ACK packets in owner uid filter.
    $IPTABLES -A aicfmessenger_out -o lo -p tcp --sport $AICF_MESSENGER_PORT -s 127.0.0.1 -m owner ! --uid-owner $AICF_MESSENGER_SERVICE_UID -j DROP
}

aicf_messenger_firewall_start() {
    local AICF_RUNNING=`$GETPROP aicfmessenger_enable`
    if [ $AICF_RUNNING -eq "1" ]; then
        print "aicf_messenger_firewall_setup"
        local AICF_MESSENGER_CLIENT_UID='aicf'
        local AICF_MESSENGER_SERVICE_UID='aicf'
        local AICF_MESSENGER_SECURE_PORT=10001
        local AICF_MESSENGER_RESERVE_START=10002
        local AICF_MESSENGER_RESERVE_END=10006

        aicf_messenger_firewall_interface wlan0 ${AICF_MESSENGER_SECURE_PORT} ${AICF_MESSENGER_RESERVE_START} ${AICF_MESSENGER_RESERVE_END}
        aicf_messenger_firewall_interface br0 ${AICF_MESSENGER_SECURE_PORT} ${AICF_MESSENGER_RESERVE_START} ${AICF_MESSENGER_RESERVE_END}
        aicf_messenger_firewall_common ${AICF_MESSENGER_CLIENT_UID} ${AICF_MESSENGER_SERVICE_UID} ${AICF_MESSENGER_SECURE_PORT}
    fi
}

# Firewall settings for P2P interface
p2p_firewall_start () {
    print "Setting up P2P firewall settings on $P2PIF"

    COMPANION_APP_TCPTUNNEL_PORT=$(get_companion_app_tcptunnel_port)

    # Default policy for all chains: DROP
    $IPTABLES -P INPUT DROP
    $IPTABLES -P OUTPUT DROP
    $IPTABLES -P FORWARD DROP

    # Setup ip tables to reject all non-essential traffic
    # Redirect all DNS traffic to ourselves. This is necessary when the client device
    # has a static DNS address configured
    $IPTABLES -t nat -A PREROUTING -i "$P2PIF" -p udp --dport 53 -j DNAT --to ${OOBEIP}
    # ACCEPT all DNS traffic
    $IPTABLES -A INPUT -i "$P2PIF" -p udp --dport 53 -j ACCEPT
    # ACCEPT all DHCP traffic
    $IPTABLES -A INPUT -i "$P2PIF" -p udp --dport 67:68 --sport 67:68 -j ACCEPT
    # ACCEPT all incoming OOBE webserver traffic
    $IPTABLES -A INPUT -i "$P2PIF" -p tcp --dport 8080 -j ACCEPT
    $IPTABLES -A INPUT -i "$P2PIF" -p tcp --dport ${COMPANION_APP_TCPTUNNEL_PORT} -j ACCEPT

    # Allow all outgoing traffic
    $IPTABLES -A OUTPUT -o "$P2PIF" -j ACCEPT
}

# Firewall settings for P2P interface
p2p_firewall_stop () {
    print "Disabling P2P firewall settings on $P2PIF"

    COMPANION_APP_TCPTUNNEL_PORT=$(get_companion_app_tcptunnel_port)

    # Delete all rules setup by p2p_firewall_start
    # Delete DNS redirection
    $IPTABLES -t nat -D PREROUTING -i "$P2PIF" -p udp --dport 53 -j DNAT --to ${OOBEIP}
    # Delete ACCEPT all DNS traffic
    $IPTABLES -D INPUT -i "$P2PIF" -p udp --dport 53 -j ACCEPT
    # Delete ACCEPT all DHCP traffic
    $IPTABLES -D INPUT -i "$P2PIF" -p udp --dport 67:68 --sport 67:68 -j ACCEPT
    # Delete ACCEPT all incoming OOBE webserver traffic
    $IPTABLES -D INPUT -i "$P2PIF" -p tcp --dport 8080 -j ACCEPT
    $IPTABLES -D INPUT -i "$P2PIF" -p tcp --dport ${COMPANION_APP_TCPTUNNEL_PORT} -j ACCEPT

    # Delete Allow all outgoing traffic
    $IPTABLES -D OUTPUT -o "$P2PIF" -j ACCEPT

    # below is a temporary change.
    print "killing dnsmasq.."
    kill -9 `cat $DNSMASQ_DATA_PATH"dnsmasq.pid"`
}

nat_firewall_start () {
    PROP_COMPANION_IP="lab126.p2p.companion.app.ip"
    IP=`getprop $PROP_COMPANION_IP`
    if [ "x$IP" == "x" ]; then
        print "$PROP_COMPANION_IP is empty, failed to enable NAT"
        return
    fi
    print "enabling ip_forward"
    echo 1 > /proc/sys/net/ipv4/ip_forward

    # Add rules for forwarding and NAT-ing traffic for the companion
    # app IP if necessary.
    $IPTABLES -C FORWARD -p tcp -s ${IP} -i ${P2PIF} -o wlan0 -j ACCEPT

    if [ $? -ne 0 ]; then
        # Accept tcp forwarding traffic
        print "enabling NAT for $IP only"
        iptables -A FORWARD -p tcp -s $IP -i ${P2PIF} -o wlan0 -j ACCEPT
        iptables -A FORWARD -p tcp -m state --state RELATED,ESTABLISHED -j ACCEPT
        # Masquerade all NAT traffic
        iptables -t nat -I natctrl_nat_POSTROUTING -o wlan0 -j MASQUERADE
    fi

    print "detecting nameserver"
    # Save nameserver to a file
    if valid_ipv4 ${DNS1IP}; then echo "nameserver ${DNS1IP}" > $DNSMASQ_DATA_PATH"resolv.dnsmasq";
    elif valid_ipv4 ${DNS2IP}; then echo "nameserver ${DNS2IP}" > $DNSMASQ_DATA_PATH"resolv.dnsmasq";
    elif valid_ipv4 ${DNS4IP}; then echo "nameserver ${DNS4IP}" > $DNSMASQ_DATA_PATH"resolv.dnsmasq";
    elif valid_ipv4 ${DNS5IP}; then echo "nameserver ${DNS5IP}" > $DNSMASQ_DATA_PATH"resolv.dnsmasq";
    fi
    echo "nameserver 8.8.8.8" >> $DNSMASQ_DATA_PATH"resolv.dnsmasq";
    chmod 644 $DNSMASQ_DATA_PATH"resolv.dnsmasq"

    print "applying nameserver"
    # Reload dnsmasq to use upstream nameserver from the file
    kill -s HUP `cat $DNSMASQ_DATA_PATH"dnsmasq.pid"`
}

nat_firewall_stop () {
    PROP_COMPANION_IP="lab126.p2p.companion.app.ip"
    IP=`getprop $PROP_COMPANION_IP`
    if [ "x$IP" == "x" ]; then
        print "$PROP_COMPANION_IP is empty, failed to enable NAT"
        return
    fi
    # cleanup
    if [ -e "$OTBR_BIN" ]; then
        print "keeping ip_foward for Openthread"
        # Delete tcp forwarding rule from NAT setup
        for interface in "${INTERFACE_LIST[@]}"
        do
            iptables -D FORWARD -p tcp -s $IP -i ${P2PIF} -o ${interface} -j ACCEPT
        done
        iptables -D FORWARD -p tcp -m state --state RELATED,ESTABLISHED -j ACCEPT
    else
        print "disabling ip_forward"
        echo 0 > /proc/sys/net/ipv4/ip_forward

        # Stop accepting forward traffic
        print "Flushing IPv4 FORWARD rules"
        iptables -F FORWARD
    fi
    # Delete NAT masquerade rule.
    iptables -t nat -D POSTROUTING -o wlan0 -j MASQUERADE

    print "clearing nameserver"
    echo "" > $DNSMASQ_DATA_PATH"resolv.dnsmasq"
    chmod 644 $DNSMASQ_DATA_PATH"resolv.dnsmasq"

    print "applying nameserver"
    kill -s HUP `cat $DNSMASQ_DATA_PATH"dnsmasq.pid"`
}

tcp_tunnel_start () {
    COMPANION_APP_TCPTUNNEL_PORT=$(get_companion_app_tcptunnel_port)

    # The companion app make authorize link code call on port number 443. OOBE apk is a prebuilt. So it cannot bind to port numbers less than 1024.
    # So, any traffic that is sent over the p2p interface to the server ip, should be redirected to a port that the OOBE apk can bind to. This port
    # on which the OOBE apk is listening is written in the system property lab126.oobe.local.listening.prt, by the OOBE apk.
    print "Enabling TCPTunnel port forwarding from ${TCPTUNNEL_LOCAL_LISTENING_PORT} to ${COMPANION_APP_TCPTUNNEL_PORT} on $P2PIF"

    iptables -A INPUT -i "$P2PIF" -p tcp --dport ${TCPTUNNEL_LOCAL_LISTENING_PORT} -j ACCEPT
    iptables -t nat -A PREROUTING -i "$P2PIF" -p tcp --dport ${COMPANION_APP_TCPTUNNEL_PORT} -d ${OOBEIP} -j DNAT --to-destination ${OOBEIP}:${TCPTUNNEL_LOCAL_LISTENING_PORT}
}

tcp_tunnel_stop () {
    # cleanup
    print "Disabling TCPTunnel port forwarding"

    COMPANION_APP_TCPTUNNEL_PORT=$(get_companion_app_tcptunnel_port)

    iptables -D INPUT -i "$P2PIF" -p tcp --dport ${TCPTUNNEL_LOCAL_LISTENING_PORT} -j ACCEPT
    iptables -t nat -D PREROUTING -i "$P2PIF" -p tcp --dport ${COMPANION_APP_TCPTUNNEL_PORT} -d ${OOBEIP} -j DNAT --to-destination ${OOBEIP}:${TCPTUNNEL_LOCAL_LISTENING_PORT}
}

start_setup_firewall () {

    case "$1" in
        default)
            default_firewall_setup
            default_ipv6_firewall_setup
            alexa_hybrid_firewall_setup
            aicf_messenger_firewall_start
            ;;
        p2p)
            shift
            p2p_firewall_start
            ;;
        nat)
            shift
            nat_firewall_start
            ;;
        port_forwarding)
            shift
            tcp_tunnel_start
            ;;
        *)
            exit 1
            ;;
    esac
}

stop_setup_firewall () {

    case "$1" in
        p2p)
            shift
            p2p_firewall_stop
            nat_firewall_stop
            ;;
        nat)
            shift
            nat_firewall_stop
            ;;
        port_forwarding)
            shift
            tcp_tunnel_stop
            ;;
        *)
            exit 1
            ;;
    esac
}

case "$1" in
    start)
        if [ "$2" ]
        then
            shift
            # Setup any specific settings
            start_setup_firewall "$@"
            exit 0
        fi
        ;;
    stop)
        if [ "$2" ]
        then
            shift
            # Stop any specific settings
            stop_setup_firewall "$@"
            exit 0
        fi
        ;;
    *)
        exit 1
        ;;
esac

exit 1

