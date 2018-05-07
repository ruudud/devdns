#!/bin/bash
domain="${DNS_DOMAIN:-test}"
extrahosts=($EXTRA_HOSTS)
hostmachineip="${HOSTMACHINE_IP:-172.17.0.1}"
naming="${NAMING:-default}"
dnsmasq_pid=""
dnsmasq_path="/etc/dnsmasq.d/"

RESET="\e[0;0m"
RED="\e[0;31;49m"
GREEN="\e[0;32;49m"
YELLOW="\e[0;33;49m"

trap shutdown SIGINT SIGTERM

start_dnsmasq(){
  dnsmasq --keep-in-foreground &
  dnsmasq_pid=$!
}
reload_dnsmasq(){
  kill $dnsmasq_pid
  start_dnsmasq
}
shutdown(){
  echo "Shutting down..."
  kill $dnsmasq_pid
  exit 0
}
get_name(){
  local cid="$1"
  docker inspect -f '{{ .Name }}' "$cid" | sed "s,^/,,"
}
get_safe_name(){
  local name="$1"
  case "$NAMING" in
    full)
      # Replace _ with -, useful when using default Docker naming
      name=$(echo "$name" | sed 's/_/-/g')
      ;;

    *)
      # Docker allows _ in names, but other than that same as RFC 1123
      # We remove everything from "_" and use the result as record.
      if [[ ! "$name" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        name="${name%%_*}"
      fi
      ;;
  esac

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
  split_on_commas "${domain}" | while read item; do
    local name="$1"
    local record="${name}.${item}"
    local file="${dnsmasq_path}${record}.conf"

    [[ -f "$file" ]] && rm "$file"
    echo -e "${RED}- Removed record for ${record}${RESET}"
  done
}
set_container_record(){
  split_on_commas "${domain}" | while read item; do
    local cid="$1"
    local ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$cid" | head -n1)
    local name=$(get_name "$cid")
    local safename=$(get_safe_name "$name")
    local record="${safename}.${item}"
    set_record "$record" "$ip"
  done
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
  while read -r time _ event container meta; do
    case "$event" in
      start|rename)
        set_container_record "$container"
        reload_dnsmasq
        ;;
      die)
        local name=$(echo "$meta" | grep -Eow "name=[_a-z]+" | cut -d= -f2)
        [[ -z "$name" ]] && continue
        safename=$(get_safe_name "$name")

        del_container_record "$safename"
        find_and_set_prev_record "$safename"
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

split_on_commas() {
  local IFS=,
  local list=($1)
  for word in "${list[@]}"; do
    echo "$word"
  done
}

add_wildcard_record(){
  split_on_commas "${domain}" | while read item; do
    echo "address=/.${item}/${hostmachineip}" > "/etc/dnsmasq.d/${item}.conf"
    echo -e "${GREEN}+ Added *.${item} → ${hostmachineip}${RESET}"
  done
}

add_wildcard_record
add_running_containers
set_extra_records
start_dnsmasq
setup_listener
