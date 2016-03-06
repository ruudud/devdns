#!/bin/bash
#set -x
domain="${DNS_DOMAIN:-dev}"
extrahosts=($EXTRA_HOSTS)
hostmachineip="${HOSTMACHINE_IP:-172.17.0.1}"
dnsmasq_pid=""
dnsmasq_path="/etc/dnsmasq.d/"

RESET="\e[0;0m"
RED="\e[0;31;49m"
GREEN="\e[0;32;49m"
YELLOW="\e[0;33;49m"

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
  # We remove everything from "_" and use the result as record.
  if [[ ! "$name" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    name="${name%%_*}"
  fi
  echo "$name"
}
set_record(){
  local record="$1"
  local fpath="${dnsmasq_path}${record}.conf"
  local ip="$2"
  [[ -z "$ip" ]] && return 1

  local infomsg="${GREEN}+ Added ${record} → ${ip}${RESET}"
  if [[ -f "$fpath" ]]; then
    infomsg="${YELLOW}+ Replaced ${record} → ${ip}${RESET}"
  fi

  echo "address=/.${record}/${ip}" > "$fpath"
  echo -e "$infomsg"
}
del_container_record(){
  local name="$1"
  local record="${name}.${domain}"
  local file="${dnsmasq_path}${record}.conf"

  [[ -f "$file" ]] && rm "$file"
  echo -e "${RED}- Removed record for ${record}${RESET}"
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
find_and_set_prev_record(){
  local name="$1"
  local prevcid=$(docker ps -q -f "name=${name}.*" | head -n1)
  [[ -z "$prevcid" ]] && return 0

  echo -e "${YELLOW}+ Found other active container with matching name: ${name}"
  set_container_record "$prevcid"
}
setup_listener(){
  while read -r time container _ _ event; do
    case "$event" in
      start|rename)
        set_container_record "${container%%:}"
        reload_dnsmasq
        ;;
      die)
        local cid="${container%%:}"
        [[ -z "$cid" ]] && continue
        local name=$(get_safe_name "$cid")

        del_container_record "$name"
        find_and_set_prev_record "$name"
        reload_dnsmasq
        ;;
    esac
  done < <(docker events -f event=start -f event=die -f event=rename)
}
add_running_containers(){
  local ids=$(docker ps -q)
  for id in $ids; do
    set_container_record "$id"
  done
}
add_wildcard_record(){
  echo "address=/.${domain}/${hostmachineip}" > "/etc/dnsmasq.d/hostmachine.conf"
  echo -e "${GREEN}+ Added *.${domain} → ${hostmachineip}${RESET}"
}

add_wildcard_record
add_running_containers
set_extra_records
start_dnsmasq
setup_listener
