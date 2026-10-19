#!/system/bin/sh
#
# Copyright (c) 2018  Amazon.com, Inc. or its affiliates.  All rights reserved.
#
# PROPRIETARY/CONFIDENTIAL.  USE IS SUBJECT TO LICENSE TERMS.
#

AHE_BINARY=/system/bin/AlexaHybridExecutionController
AHE_CONFIG=/system/etc/ahe.config.json
AHE_INIT_SERVICE=ahe
AHE_LIBS_DIR=/system/lib/alexahybrid
LOG_BINARY=/system/bin/log

# See wiki for design choices for this restart policy
# https://wiki.labcollab.net/confluence/display/SHELBY/AHE+Process+lifecycle+on+1P+devices
# Retry intervals in minutes: 0,0,5m,1h,6h,12h,1d,3d,5d,10d
RETRY_SCHEDULE=(0 0 5 60 360 720 1440 4320 7200 14400)
RETRY_SCHEDULE_LENGTH=${#RETRY_SCHEDULE[@]}
# reset backoff attempt counter if AHE ran for more than 5 hour.
BACKOFF_RESET_DELAY_IN_SEC=18000

usage() {
  echo "Usage:       $0 [-c <command>] [-r <retry schedule multiplier>]"
  echo "(deprecated) $0 [retry schedule multiplier]"
}

parse_args() {
  while getopts ":c:r:" param; do
    case "${param}" in
      c)
        AHE_BINARY=${OPTARG}
        ;;
      r)
        RETRY_SCHEDULE_MULTIPLIER=${OPTARG}
        ;;
      *)
        usage
        exit 1
        ;;
    esac
  done
}

if [[ ${1:0:1} == "-" ]] ; then
  # Read named parameters
  parse_args "$@"
else
  # Fallback to legacy way to read first parameter.
  # Custom RETRY_SCHEDULE_MULTIPLIER is used for testing
  RETRY_SCHEDULE_MULTIPLIER=${1}
fi

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
    ${LOG_BINARY} -t AHE_WRAPPER "Delaying restart by ${retry_delay} seconds."
    sleep ${retry_delay}
  fi

  ${LOG_BINARY} -t metrics.Metrics "AlexaHybridService:init_wrapper:attempt=${attempt};CT;1:HI"
  start_time=$(date +%s)
  CRASH_RECORD="/data/alexahybrid/files/working-directory/crashRecord.txt"
  rm "$CRASH_RECORD"
  LD_LIBRARY_PATH=${AHE_LIBS_DIR} ${AHE_BINARY} --config ${AHE_CONFIG}

  if (( $? == 0 )); then
    exit 0
  fi
  # Check if there is an intentional crash
  if test -f "$CRASH_RECORD"; then
    rm "$CRASH_RECORD"
    ${LOG_BINARY} -t metrics.Metrics "AlexaHybridService:init_wrapper:intentional_crash;CT;1:HI"
    exit 0
  fi
  end_time=$(date +%s)
  update_attempt
done
