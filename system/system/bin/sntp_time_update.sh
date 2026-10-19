#!/system/bin/sh
#
# Copyright (c) 2019-2020  Amazon.com, Inc. or its affiliates.  All rights reserved.
#
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#
LOG=/system/bin/log
TAG=sntp

print() {
    $LOG -t $TAG $1
}

store_time=`getprop persist.sys.saved_time`
system_time="`date +%s`"
if (("$store_time" > "$system_time"))
then
    resp=$(date -u @$store_time)
    print "Set time on boot returned $resp"
else
    print "Did not set time on boot"
fi
