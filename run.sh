#!/bin/bash
#set -x
domain="$DNS_DOMAIN"
extrahosts=($EXTRA_HOSTS)
dnsmasq_pid=""

start_dnsmasq(){
  dnsmasq --keep-in-foreground &
  dnsmasq_pid=$!
}
reload_dnsmasq(){
  kill $dnsmasq_pid
  start_dnsmasq
}
set_record(){
  local record="$1"
  local new_ip="$2"
  echo "host-record=${record},${new_ip}" > "/etc/dnsmasq.d/${record}.conf"
  echo "Added ${record} → ${new_ip}"
}
set_container_record(){
  local cid="$1"
  local name=$(docker inspect -f '{{ .Name }}' "$cid" | sed "s,^/,,")
  if [[ ! "$name" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    echo -n "Warn: ${name}.${domain} is not a valid DNS name. "
    local newname="${name//_/-}"
    if [[ ! "$newname" =~ ^[a-zA-Z0-9.-]+$ ]]; then
      echo "Use a different container name. Ignoring."
      return 1
    else
      echo "Replaced _ with -."
      name="$newname"
    fi
  fi
  local new_ip=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' "$cid")
  local record="${name}.${domain}"
  set_record "$record" "$new_ip"
}
set_extra_records(){
  for record in "${extrahosts[@]}"; do
    local host=${record%=*}
    local ip=${record#*=}
    set_record "$host" "$ip"
  done
}
setup_listener(){
  while read -r time container rest; do
    set_container_record "${container%%:}"
    reload_dnsmasq
  done < <(docker events -f event=start)
}
add_running_containers(){
  local ids=$(docker ps -q)
  for id in $ids; do
    set_container_record "$id"
  done
}

add_running_containers
set_extra_records
start_dnsmasq
setup_listener


