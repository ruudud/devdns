#!/bin/bash
#set -x
domain="${DNS_DOMAIN:-dev}"
extrahosts=($EXTRA_HOSTS)
osx="${OSX:-false}"
dnsmasq_pid=""
dnsmasq_path="/etc/dnsmasq.d/"

start_dnsmasq(){
  dnsmasq --keep-in-foreground &
  dnsmasq_pid=$!
}
reload_dnsmasq(){
  kill $dnsmasq_pid
  start_dnsmasq
}
get_safe_name(){
  local cid="$1"
  local name=$(docker inspect -f '{{ .Name }}' "$cid" | sed "s,^/,,")
  # Docker allows _ in names, but other than that same as RFC 1123
  if [[ ! "$name" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    name="${name//_/-}"
  fi
  echo "$name"
}
set_record(){
  local record="$1"
  local ip="$2"
  echo "host-record=${record},${ip}" > "${dnsmasq_path}${record}.conf"
  echo "+ Added ${record} → ${ip}"
}
del_container_record(){
  local cid="$1"
  local name=$(get_safe_name "$cid")
  local record="${name}.${domain}"

  rm "${dnsmasq_path}${record}.conf"
  echo "- Removed record for ${record}"
}
set_container_record(){
  local cid="$1"
  local ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' "$cid")
  local name=$(get_safe_name "$cid")
  local record="${name}.${domain}"
  set_record "$record" "$ip"
}
set_extra_records(){
  for record in "${extrahosts[@]}"; do
    local host=${record%=*}
    local ip=${record#*=}
    set_record "$host" "$ip"
  done
}
setup_listener(){
  while read -r time container _ _ event; do
    case "$event" in
      start)
        set_container_record "${container%%:}"
        reload_dnsmasq
        ;;
      stop)
        del_container_record "${container%%:}"
        reload_dnsmasq
        ;;
      *)
        echo "wut?"
        ;;
    esac
  done < <(docker events -f event=start -f event=stop)
}
add_running_containers(){
  local ids=$(docker ps -q)
  for id in $ids; do
    set_container_record "$id"
  done
}
add_wildcard_record(){
  local hostmachineip
  if [[ "$OSX" == "true" ]]; then
    hostmachineip="192.168.59.3"
  else
    hostmachineip="172.17.42.1"
  fi
  echo "address=/.${domain}/${hostmachineip}" > "/etc/dnsmasq.d/hostmachine.conf"
  echo "+ Added *.${domain} → ${hostmachineip}"
}

add_wildcard_record
add_running_containers
set_extra_records
start_dnsmasq
setup_listener

