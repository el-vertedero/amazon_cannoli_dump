#!/system/bin/sh

LOG=/system/bin/log
TAG=pre_factory_reset

if [ -d "/cache/recovery" ]; then
   rm -rf /cache/recovery/*
else
   # We shouldn't reach here. Leaving it for historical reasons.
   mkdir /cache/recovery
fi

# Gets the maximum size of allow list files from property
al_maxstore=$(getprop ro.recovery.wl.maxstore)

# Get factory reset type
factory_reset_type=$(getprop persist.amazon.factoryreset)
DEEP_FACTORY_RESET=DEEP
SUPER_DEEP_FR=SUPER_DEEP

# Copy the conf file from file system to recovery
fdrw_file="/system/etc/fdrw_default.conf"
recovery_fdrw="/cache/recovery/fdrw.conf"
if [ -f "$fdrw_file" ]; then
     cp $fdrw_file $recovery_fdrw
fi

# Populate the command with parameters for filesystem
echo "--wipe_data\n" >> /cache/recovery/command
echo "--data_restore=$recovery_fdrw\n" >> /cache/recovery/command
echo "--restore_max=$al_maxstore\n" >> /cache/recovery/command

if [ "$factory_reset_type" = "$SUPER_DEEP_FR" ]; then
    $LOG -t $TAG "Super Deep FR"
    # Allow list for metrics, device only data, no customer data
    echo "5 /data/misc/fmonitor" >> $recovery_fdrw
elif [ "$factory_reset_type" = "$DEEP_FACTORY_RESET" ]; then
    echo "" >> $recovery_fdrw
    echo "5 /data/davs/resources" >> $recovery_fdrw
    echo "8 /data/davs/requests" >> $recovery_fdrw
    # Allow list for metrics
    echo "5 /data/misc/fmonitor" >> $recovery_fdrw
    $LOG -t $TAG "DEEP FR"
else
    echo "" >> $recovery_fdrw
    echo "5 /data/davs/resources" >> $recovery_fdrw
    echo "8 /data/davs/requests" >> $recovery_fdrw
    # Allow list for metrics
    echo "5 /data/misc/fmonitor" >> $recovery_fdrw
    # Allow list Smart Home Data
    echo "8 /data/securedStorageLocation/SmartHome" >> $recovery_fdrw
    echo "8 /data/misc/halo/var/sqlite" >> $recovery_fdrw
    echo "8 /data/misc/openthread/node.flash" >> $recovery_fdrw
    echo "8 /data/misc/zigbee" >> $recovery_fdrw
    echo "8 /data/ace/kvstorage/zigbee.db" >> $recovery_fdrw
    echo "8 /data/misc/blemesh" >> $recovery_fdrw
    echo "8 /data/misc/smarthome_shared" >> $recovery_fdrw
    echo "8 /data/misc/bluetooth" >> $recovery_fdrw
    echo "8 /data/misc/bluedroid" >> $recovery_fdrw

    $LOG -t $TAG "Shallow FR"
fi

#if it's mt8512 or mt8519 we need to set bootmode to 3
cat /proc/cmdline | egrep "androidboot.hardware=mt8512|androidboot.hardware=mt8519" && idme bootmode 3

sync
/system/bin/reboot "recovery"
