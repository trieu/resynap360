#!/bin/bash

# Script to monitor cardinality of unique Redis sets
# Usage: ./monitor_unique_keys.sh

REDIS_PORT=6380

watch -n 1 '
  echo "========================="
  echo "📅 Timestamp: $(date)"
  echo "========================="
  echo

  redis-cli -p '"$REDIS_PORT"' SCARD unique:emails | awk "{ print \"📧 unique:emails        => \" \$1 }"
  redis-cli -p '"$REDIS_PORT"' SCARD unique:visids | awk "{ print \"🆔 unique:visids        => \" \$1 }"
  redis-cli -p '"$REDIS_PORT"' SCARD unique:phone_numbers | awk "{ print \"📱 unique:phone_numbers => \" \$1 }"

  echo
'
