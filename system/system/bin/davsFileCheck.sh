#!/system/bin/sh

# We see smart home davs data corruption in some customer device.
# One possible reason may be due to sudden power loss during factory
# reset while SW restore the davs data.
# In case of corruption, we request puffin team to add integration check
# for davs data in DEE-192525.
# Temporary workaround: find the corrupted folder and delete.

function echo_dmesg()
{
    echo $@ > /dev/kmsg
}

# Check if any file with root permission
find /data/davs/ -user root | grep .

# Check return status and operate accordingly
if [ $? -eq 0 ] ; then
    echo_dmesg "davs corruption found: wipe davs fully"
    rm -rf /data/davs/*
else
    echo_dmesg "davs no corruption"
fi
