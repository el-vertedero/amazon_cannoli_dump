#!/system/bin/sh

HALO_PATH=/vendor/bin
VETC_PATH=/vendor/etc/halo_config
DETC_PATH=/mnt/halo/etc
HALO_REGP=/data/vendor/halo/run/mfg

[ -f ${HALO_PATH}/halo_common_lib.sh ] && . ${HALO_PATH}/halo_common_lib.sh

LOG_TAG="halo-services"

halo_cli_get() {
    halo_cli "$1" > "$2" 2>> $HLOG
    if [ $? -ne 0 ]; then
        halo_log_error $LOG_TAG  "*** Failed to request from Nordic: $1 ***"
    rm $2
    fi
}

# update boot reason
if [ "$#" -eq "0" ]; then
    if [ -e ${HALO_BOOT_RSN} ]; then
        # reboot_reason file is already exist, this is a reboot
        echo "normal_reboot" > ${HALO_BOOT_RSN}
    else
        # create reboot_reason file and put initial boot reason
        touch ${HALO_BOOT_RSN}
        echo "initial_boot" > ${HALO_BOOT_RSN}
    fi
fi

if [ "$1" == "config" ]; then
    halo_log_info $LOG_TAG  "*** setting build config: $1 ***"

    enable_ringnet=$(getprop vendor.halo.enable.ringnet)
    enable_sidewalk=$(getprop vendor.halo.enable.sidewalk)

    halo_log_info $LOG_TAG  "*** enable_ringnet=${enable_ringnet} ***"
    halo_log_info $LOG_TAG  "*** enable_sidewalk=${enable_sidewalk} ***"

    #copy conf. files
    cp -aRfP $VETC_PATH/* $DETC_PATH/.

    if [ "${enable_ringnet}" == "true" ] && [ "${enable_sidewalk}" == "true" ] ; then
        setprop vendor.halo.buildtype halo_full
    elif [ "${enable_ringnet}" == "true" ] ; then
        setprop vendor.halo.buildtype halo_ringnet
    elif [ "${enable_sidewalk}" == "true" ] ; then
        setprop vendor.halo.buildtype halo_sidewalk
    fi

    if [ "${enable_ringnet}" == "true" ] ; then
        halo_log_info $LOG_TAG "Starting ringnet plugin"
    fi

    if [ "${enable_sidewalk}" == "true" ] ; then
        halo_log_info $LOG_TAG "Starting sidewalk plugin"
        echo $(getprop ro.product.config.type) > $MFG/gateway_device_type
    fi

    halo_log_info $LOG_TAG  "setting build config $(getprop vendor.halo.buildtype)"
    sync /mnt/halo
    if [ "$(ls $DETC_PATH/hub-core.conf.d/*.conf)" != "" ]; then
        setprop vendor.halo.hubcore.config true
    fi
    exit 0;
fi

if [ "$1" == "prov" ]; then
    halo_log_info $LOG_TAG  "*** Clean up hub-core after prov: $1 ***"
    rm $DETC_PATH/hub-core.conf.d/80_ras-hosts.conf
    exit 0;
fi

halo_log_info $LOG_TAG  "*** >>> Starting Halo Services  <<< ***"

if [ -f $HLOG ]; then
    rm $HLOG
fi
if [ ! -s $MFG/ringnetid ]; then
    halo_log_info $LOG_TAG "Creating $MFG/ringnetid";
    halo_cli_get get_uuid $MFG/ringnetid;
fi
if [ ! -s $MFG/serial_no ]; then
    halo_log_info $LOG_TAG "Creating $MFG/serial_no";
    halo_cli_get get_serial_no $MFG/serial_no;
fi
if [ ! -s $MFG/authtoken ]; then
    halo_log_info $LOG_TAG "Creating $MFG/authtoken";
    halo_cli_get get_auth_token $MFG/authtoken;
fi
if [ ! -s $MFG/serial ]; then
    halo_log_info $LOG_TAG "Creating $MFG/serial";
    echo $((0x$(cat $MFG/ringnetid) & 0x1FFFFFFFFF)) > $MFG/serial;
fi

if [ ! -s $HDIR/50_ras-auth_keys.conf ]; then
    halo_log_info $LOG_TAG "Creating $HDIR/50_ras-auth_keys.conf";
    echo -e "ras_connection {\r\n\tauth_keys = $(cat $MFG/serial):$(cat $MFG/authtoken)\r\n}" > $HDIR/50_ras-auth_keys.conf
fi

#Set the healthcheck if ringnetid is populated
if [ -s $MFG/ringnetid ]; then
    setprop vendor.halo.healthcheck true
else
    setprop vendor.halo.healthcheck false
fi

ringnetid=`cat $MFG/ringnetid`
serial_no=`cat $MFG/serial_no`
setprop vendor.halo.ringnetid $ringnetid
setprop vendor.halo.serial_no $serial_no
halo_log_info $LOG_TAG  "*** >>> Halo Services Exit <<< ***"
