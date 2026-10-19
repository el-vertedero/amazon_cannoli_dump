#!/system/bin/sh
#
# Copyright (c) 2018  Amazon.com, Inc. or its affiliates.  All rights reserved.
#
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#

echo "Entering power save mode" > /dev/kmsg

# Disable wifi/bt/zigbee
for dir in /sys/class/rfkill/*
do
  echo 0 >$dir/state
done

