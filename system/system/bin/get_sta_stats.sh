#
# Copyright (c) 2022 - 2026 Amazon.com, Inc. or its affiliates.  All rights reserved.
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#

# get_sta_stats.sh
#
# Query associated STAs from the softAP via hostapd_cli.
#   action=client    : dump per-STA stats (iwpriv) to $logfile
#   action=analytics : print "<mac>, <auth>" per STA (open/wpa2/wpa3/unknown)
#
# Usage: get_sta_stats.sh <socket> <action> <logfile> <hostapd_cli_path> <iwpriv_path>
#
#!/system/bin/sh

iwpriv_path=$5
hostapd_cli_path=$4
logfile=$3
action=$2
socket=$1

MAC=""
WPA=""
AKM=""

print_station() {
    if [ -z "$WPA" ]; then
        echo "$MAC, open"
        return
    fi
    mode="unknown"
    case "$AKM" in
        00-0f-ac-8|00-0f-ac-9|00-0f-ac-24|00-0f-ac-25)  # SAE family
            mode="wpa3" ;;
        00-0f-ac-2|00-0f-ac-4|00-0f-ac-6|00-0f-ac-19|00-0f-ac-20)  # PSK family
            mode="wpa2" ;;
    esac
    echo "$MAC, $mode"
}

if [ "$action" = "client" ]; then
    # grep the line starting with MAC address format, without any trailing character
    $hostapd_cli_path -i ap0 -p $socket all_sta | grep -o -E '^(([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}$)' > $logfile

    while IFS= read -r mac_addr
    do
        echo "Station : $mac_addr"
        $iwpriv_path wlan0 driver "stats $mac_addr"
        $iwpriv_path wlan0 driver "get_sta_statistics $mac_addr"

    done < $logfile
fi

if [ "$action" = "analytics" ]; then
    all_sta_out=$($hostapd_cli_path -i ap0 -p $socket all_sta) || exit 1

    printf '%s\nEOF\n' "$all_sta_out" | while read -r LINE; do
        case "$LINE" in
            [0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:*)
                [ -n "$MAC" ] && print_station
                MAC="$LINE"
                WPA=""
                AKM=""
                ;;
            wpa=*)
                WPA="${LINE#wpa=}"
                ;;
            AKMSuiteSelector=*)
                AKM="${LINE#AKMSuiteSelector=}"
                ;;
            EOF)
                if [ -n "$MAC" ]; then print_station; fi
                ;;
        esac
    done

    exit 0
fi

