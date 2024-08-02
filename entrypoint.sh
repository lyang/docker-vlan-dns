#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

initialize() {
  normalize-network-id
  config-servers
  start-dnsmasq
  initialize-host-files
  monitor-system-event
}

normalize-network-id() {
  DOCKER_NETWORK_ID=$(docker network inspect $DOCKER_NETWORK_ID | jq --raw-output '.[].Name')
}

config-servers() {
  local servers;
  IFS=';' read -ra servers <<< "$DNS_SERVERS"
  for server in "${servers[@]}"; do
    local entry="server=$server"
    local file="$CONF_DIR/servers.conf"
    echo "Adding entry $entry to $file"
    echo "$entry" >> $file
  done
}

start-dnsmasq() {
  local gateway=$(find-gateway)
  /usr/sbin/dnsmasq \
    --conf-dir=$CONF_DIR \
    --hostsdir=$HOSTSDIR \
    --domain=$DOMAIN_NAME \
    --local=/$DOMAIN_NAME/$gateway
}

find-gateway() {
  docker network inspect $DOCKER_NETWORK_ID | jq --raw-output '.[].IPAM.Config[0].Gateway'
}

initialize-host-files() {
  echo "Initializing host files for containers attached to $DOCKER_NETWORK_ID"
  local containers=($(find-containers $DOCKER_NETWORK_ID))
  for container in "${containers[@]}"; do
    update-host-file $container
  done
}

find-containers() {
  docker network inspect $1 | jq --raw-output '.[].Containers | keys.[]'
}

update-host-file() {
  local file="$HOSTSDIR/$1"
  local ip=$(find-container-ip $1)
  local name=$(find-container-name $1)
  local hostname=$(find-container-hostname $1)
  local service=$(find-service-name $1)
  local entry=""
  if [ -n "$service" ]; then
    entry+="$ip $service\n"
  fi
  entry+="$ip $name\n"
  entry+="$ip $hostname\n"
  printf "Adding entries for $name:\n$entry"
  printf "$entry" > $file
}

find-container-ip() {
  docker container inspect $1 | jq --raw-output ".[].NetworkSettings.Networks.\"$DOCKER_NETWORK_ID\".IPAddress"
}

find-container-name() {
  docker container inspect $1 | jq --raw-output '.[].Name[1:]'
}

find-container-hostname() {
  docker container inspect $1 | jq --raw-output '.[].Config.Hostname'
}

find-service-name() {
  docker container inspect $1 | jq --raw-output '.[].Config.Labels["com.docker.compose.service"] // empty'
}

monitor-system-event() {
  echo "Monitoring docker system events"
  docker events --filter network=$DOCKER_NETWORK_ID --format '{{json .}}' | jq --unbuffered --raw-output '(.Actor.Attributes.container) + " " + (.Action)' | handle-event
}

handle-event() {
  while read container action; do
    case $action in
      connect)
        echo "$container connected to $DOCKER_NETWORK_ID"
        update-host-file $container
        ;;
      disconnect)
        echo "$container disconnected from $DOCKER_NETWORK_ID"
        remove-host-file $container
        ;;
      *)
        echo "Unexpected action: $action"
        ;;
    esac
  done
}

remove-host-file() {
  local file="$HOSTSDIR/$1"
  echo "Deleting $file"
  rm -rf $file
}

initialize
