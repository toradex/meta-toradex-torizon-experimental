#!/usr/bin/env sh

# Found here: https://github.com/willfarrell/docker-autoheal

# shellcheck disable=2039
set -eo pipefail

DOCKER_SOCK=${DOCKER_SOCK:-/var/run/docker.sock}
UNIX_SOCK=""
CURL_TIMEOUT=${CURL_TIMEOUT:-30}

# only use unix domain socket if no TCP endpoint is defined
case "${DOCKER_SOCK}" in
  "tcp://"*) HTTP_ENDPOINT="$(echo ${DOCKER_SOCK} | sed 's#tcp://#https://#')"
             CA="--cacert /certs/ca.pem"
             CLIENT_KEY="--key /certs/client-key.pem"
             CLIENT_CERT="--cert /certs/client-cert.pem"
             ;;
  *)         HTTP_ENDPOINT="http://localhost"
             UNIX_SOCK="--unix-socket ${DOCKER_SOCK}"
             ;;
esac

AUTOHEAL_CONTAINER_LABEL=${AUTOHEAL_CONTAINER_LABEL:-autoheal}
AUTOHEAL_START_PERIOD=${AUTOHEAL_START_PERIOD:-0}
AUTOHEAL_INTERVAL=${AUTOHEAL_INTERVAL:-300}
AUTOHEAL_DEFAULT_STOP_TIMEOUT=${AUTOHEAL_DEFAULT_STOP_TIMEOUT:-10}

docker_curl() {
  curl --max-time "${CURL_TIMEOUT}" --no-buffer -s \
  ${CA} ${CLIENT_KEY} ${CLIENT_CERT} \
  ${UNIX_SOCK} \
  "$@"
}

# shellcheck disable=2039
get_container_info() {
  $label_filter
  $url

  # Set container selector
  if [ "$AUTOHEAL_CONTAINER_LABEL" = "all" ]
  then
    label_filter=""
  else
    label_filter=",\"label\":\[\"${AUTOHEAL_CONTAINER_LABEL}=true\"\]"
  fi
  url="${HTTP_ENDPOINT}/containers/json?filters=\{\"health\":\[\"unhealthy\"\]${label_filter}\}"
  docker_curl "$url"
}

# shellcheck disable=2039
restart_container() {
  container_id="$1"
  timeout="$2"

  docker_curl -f -X POST "${HTTP_ENDPOINT}/containers/${container_id}/restart?t=${timeout}"
}

# SIGTERM-handler
term_handler() {
  exit 143  # 128 + 15 -- SIGTERM
}

# shellcheck disable=2039
trap 'kill $$; term_handler' SIGTERM

if [ "$1" = "autoheal" ] && [ -e "$DOCKER_SOCK" ];then
  # Delayed startup
  if [ "$AUTOHEAL_START_PERIOD" -gt 0 ]
  then
  echo "Monitoring containers for unhealthy status in $AUTOHEAL_START_PERIOD second(s)"
    sleep "$AUTOHEAL_START_PERIOD"
  fi

  while true
  do
    echo "Checking the health of running containers..."
    STOP_TIMEOUT=".Labels[\"autoheal.stop.timeout\"] // $AUTOHEAL_DEFAULT_STOP_TIMEOUT"
    get_container_info | \
      jq -r "foreach .[] as \$CONTAINER([];[]; \$CONTAINER | .Id, .Names[0], .State, ${STOP_TIMEOUT})" | \
      while read -r CONTAINER_ID && read -r CONTAINER_NAME && read -r CONTAINER_STATE && read -r TIMEOUT
    do
      # shellcheck disable=2039
      CONTAINER_SHORT_ID=$(echo "${CONTAINER_ID}" | cut -c 1-12)
      DATE=$(date +%d-%m-%Y" "%H:%M:%S)

      if [ "$CONTAINER_NAME" = "null" ]
      then
        echo "$DATE Container name of (${CONTAINER_SHORT_ID}) is null, which implies container does not exist - don't restart" >&2
      elif [ "$CONTAINER_STATE" = "restarting" ]
      then
        echo "$DATE Container $CONTAINER_NAME (${CONTAINER_SHORT_ID}) found to be restarting - don't restart"
      else
        echo "$DATE Container $CONTAINER_NAME (${CONTAINER_SHORT_ID}) found to be unhealthy - Restarting container now with ${TIMEOUT}s timeout"
        if ! restart_container "$CONTAINER_ID" "$TIMEOUT"
        then
          echo "$DATE Restarting container $CONTAINER_SHORT_ID failed" >&2
        fi
      fi
    done
    sleep "$AUTOHEAL_INTERVAL"
  done

else
  exec "$@"
fi
