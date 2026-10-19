#!/system/bin/sh
ARGS="--bind-interfaces --no-poll --dhcp-authoritative --dhcp-option-force=43"
ARGS=" ${ARGS} --pid-file=/data/misc/dhcp/dnsmasq.pid"
ARGS=" ${ARGS} --resolv-file=/data/misc/dhcp/resolv.dnsmasq"
P2PIPADDRESS=$(getprop p2p.server.addr)
DHCPRANGE=$(getprop p2p.server.dhcpRange)
REG_ENDPOINT_FILE_NAME=/system/etc/registration_endpoint_host_names.csv

#log -p i -t p2p_dnsmasq.sh "starting dnsmasq"

read_hosts () {
    local IFS=,
    read KEY HOST_NAME
}

while read_hosts;
do
    if [ -n "$HOST_NAME" ]
    then
        DNSMASQ_ENDPOINT_ARGS="-A /$HOST_NAME/$P2PIPADDRESS"'\n'"${DNSMASQ_ENDPOINT_ARGS}"
    fi
done < $REG_ENDPOINT_FILE_NAME

DNSMASQ_ENDPOINT_ARGS=$(echo ${DNSMASQ_ENDPOINT_ARGS} | sort -u )

echo "$DNSMASQ_ENDPOINT_ARGS"
if [ -n "$P2PIPADDRESS" ]
then
    ARGS=" ${ARGS} -a ${P2PIPADDRESS}"
    ARGS=" ${ARGS} ${DNSMASQ_ENDPOINT_ARGS}"
fi

if [ -n "$DHCPRANGE" ]
then
    ARGS=" -F ${DHCPRANGE}${ARGS}"
fi
#log -p i -t p2p_dnsmasq.sh "CALLING DNSMASQ WITH: $* $ARGS"
/system/bin/dnsmasq $* $ARGS
