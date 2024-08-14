#!/bin/bash

source /etc/hysteria/core/scripts/path.sh

SHOW_TRAFFIC=true

while getopts ":u:t" opt; do
  case ${opt} in
    u )
      USERNAME=$OPTARG
      ;;
    t )
      SHOW_TRAFFIC=false
      ;;
    \? )
      echo "Usage: $0 -u <username> [-t]"
      exit 1
      ;;
  esac
done

if [ -z "$USERNAME" ]; then
  echo "Usage: $0 -u <username> [-t]"
  exit 1
fi

if [ ! -f "$USERS_FILE" ]; then
  echo "users.json file not found at $USERS_FILE!"
  exit 1
fi

USER_INFO=$(jq -r --arg username "$USERNAME" '.[$username] // empty' "$USERS_FILE")

if [ -z "$USER_INFO" ]; then
  echo "User '$USERNAME' not found in $USERS_FILE."
  exit 1
fi

echo "$USER_INFO" | jq .

if [ "$SHOW_TRAFFIC" = true ]; then
  if [ ! -f "$TRAFFIC_FILE" ]; then
    echo "No traffic data file found at $TRAFFIC_FILE. User might not have connected yet."
    exit 0
  fi

  TRAFFIC_INFO=$(jq -r --arg username "$USERNAME" '.[$username] // empty' "$TRAFFIC_FILE")

  if [ -z "$TRAFFIC_INFO" ]; then
    echo "No traffic data found for user '$USERNAME' in $TRAFFIC_FILE. User might not have connected yet."
  else
    echo "$TRAFFIC_INFO" | jq .
  fi
fi

exit 0