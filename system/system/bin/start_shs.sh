#!/system/bin/sh
#
# Copyright (c) 2020  Amazon.com, Inc. or its affiliates.  All rights reserved.
#
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#

SHS_BINARY=/system/bin/SkillContainer
SHS_CONFIG=/system/etc/shs.config.json
SHS_LIBS_DIR=/system/lib/ah_shs:/system/lib:/system/lib/alexahybrid

# See wiki for design choices for this restart policy
# https://wiki.labcollab.net/confluence/display/SHELBY/AHE+Process+lifecycle+on+1P+devices
# Retry intervals in minutes: 0,0,5m,1h,6h,12h,1d,3d,5d,10d
RETRY_SCHEDULE=(0 0 5 60 360 720 1440 4320 7200 14400)
RETRY_SCHEDULE_LENGTH=${#RETRY_SCHEDULE[@]}
# reset backoff attempt counter if AHE ran for more than 5 hour.
BACKOFF_RESET_DELAY_IN_SEC=18000
# Used for testing
RETRY_SCHEDULE_MULTIPLIER=${1}

if [ -z ${RETRY_SCHEDULE_MULTIPLIER} ]; then
  # seconds in a minute
  RETRY_SCHEDULE_MULTIPLIER=60
fi

update_attempt() {
  if (( (${end_time} - ${start_time}) >= ${BACKOFF_RESET_DELAY_IN_SEC} )); then
    attempt=0
  fi

  attempt=$((attempt + 1))

  if (( ${attempt} >= ${RETRY_SCHEDULE_LENGTH} )); then
    attempt=$((RETRY_SCHEDULE_LENGTH - 1))
  fi
}

update_retry_delay() {
  retry_delay=${RETRY_SCHEDULE[${1}]}
  retry_delay=$((retry_delay * RETRY_SCHEDULE_MULTIPLIER))
  # Add upto 10% jitter
  jitter=$(( RANDOM % 10 ))
  jitter=$(( jitter * retry_delay / 100 ))
  retry_delay=$(( retry_delay + jitter ))
}

attempt=0
while true; do
  update_retry_delay ${attempt}

  if (( ${attempt} > 0 )); then
    sleep ${retry_delay}
  fi

  start_time=$(date +%s)
  LD_LIBRARY_PATH=${SHS_LIBS_DIR} ${SHS_BINARY} --config ${SHS_CONFIG}
  if (( $? == 0 )); then
    exit 0
  fi
  end_time=$(date +%s)
  update_attempt
done

