#!/system/bin/sh

random_seed=/data/seed/random-seed

if [ $1 = "load" ]; then
    echo "Initializing random number generator..."
    # Carry a random seed from start-up to start-up
    # Load and then save the whole entropy pool
    if [ -f $random_seed ]; then
      cat $random_seed > /dev/urandom
    fi
else
    # Carry a random seed from shut-down to start-up
    # Save the whole entropy pool
    echo "Saving random seed..."
    while :
    do
        sleep 600 # store random seed every 10 minutes
        touch $random_seed
        chmod 600 $random_seed
        dd if=/dev/urandom of=$random_seed count=1 bs=512
    done
fi
