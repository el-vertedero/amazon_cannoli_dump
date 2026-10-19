#!/system/bin/sh
PATH=/sbin:/system/bin:/system/xbin

build_tags=$(getprop ro.build.tags)
ret=none

if [[ $build_tags == *release-keys* ]]; then
    log -t FOSFLAGS "User build"
    ret=closed
    log -t FOSFLAGS "Unset adb from persist.sys.usb.config property"
fi

echo $ret
