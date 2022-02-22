#!/usr/bin/env bash

BL=`echo "\033[36m"`
RD=`echo "\033[01;31m"`
CM='\xE2\x9C\x94\033'
GN=`echo "\033[1;92m"`
CL=`echo "\033[m"`
while true; do
    read -p "This will create a New Unprivileged Home Assistant Container LXC. Proceed(y/n)?" yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit;;
        * ) echo "Please answer yes or no.";;
    esac
done
clear
function header_info {
echo -e "${BL}

  _    _                                         _     _              _   
 | |  | |                          /\           (_)   | |            | |  
 | |__| | ___  _ __ ___   ___     /  \   ___ ___ _ ___| |_ __ _ _ __ | |_ 
 |  __  |/ _ \|  _   _ \ / _ \   / /\ \ / __/ __| / __| __/ _  |  _ \| __|
 | |  | | (_) | | | | | |  __/  / ____ \\__ \__ \ \__ \ || (_| | | | | |_ 
 |_|  |_|\___/|_| |_| |_|\___| /_/    \_\___/___/_|___/\__\__,_|_| |_|\__|
                                                                          
                                                                          
                                                 
                                                 
${CL}"
}

header_info

set -o errexit
set -o errtrace
set -o nounset
set -o pipefail
shopt -s expand_aliases
alias die='EXIT=$? LINE=$LINENO error_exit'
trap die ERR
trap cleanup EXIT

function error_exit() {
  trap - ERR
  local DEFAULT='Unknown failure occured.'
  local REASON="\e[97m${1:-$DEFAULT}\e[39m"
  local FLAG="\e[91m[ERROR] \e[93m$EXIT@$LINE"
  msg "$FLAG $REASON"
  [ ! -z ${CTID-} ] && cleanup_ctid
  exit $EXIT
}
function warn() {
  local REASON="\e[97m$1\e[39m"
  local FLAG="\e[93m[WARNING]\e[39m"
  msg "$FLAG $REASON"
}
function info() {
  local REASON="$1"
  local FLAG="\e[36m[INFO]\e[39m"
  msg "$FLAG $REASON"
}
function msg() {
  local TEXT="$1"
  echo -e "$TEXT"
}
function cleanup_ctid() {
  if $(pct status $CTID &>/dev/null); then
    if [ "$(pct status $CTID | awk '{print $2}')" == "running" ]; then
      pct stop $CTID
    fi
    pct destroy $CTID
  elif [ "$(pvesm list $STORAGE --vmid $CTID)" != "" ]; then
    pvesm free $ROOTFS
  fi
}
function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}
TEMP_DIR=$(mktemp -d)
pushd $TEMP_DIR >/dev/null

export CTID=$(pvesh get /cluster/nextid)
export PCT_OSTYPE=debian
export PCT_OSVERSION=11
export PCT_DISK_SIZE=8
export PCT_OPTIONS="
  -features nesting=1,keyctl=1,mknod=1
  -hostname homeassistant
  -net0 name=eth0,bridge=vmbr0,ip=dhcp
  -onboot 1
  -cores 2
  -memory 2048
  -unprivileged 1
"
bash -c "$(wget -qLO - https://raw.githubusercontent.com/tteck/Proxmox/unprev/create_lxc.sh)" || exit

STORAGE_TYPE=$(pvesm status -storage $(pct config $CTID | grep rootfs | awk -F ":" '{print $2}') | awk 'NR>1 {print $2}')
if [ "$STORAGE_TYPE" == "zfspool" ]; then
  warn "Some addons may not work due to ZFS not supporting 'fallocate'."
fi
LXC_CONFIG=/etc/pve/lxc/${CTID}.conf
cat <<EOF >> $LXC_CONFIG
lxc.cgroup2.devices.allow: a
lxc.cap.drop:
EOF

echo -en "${GN} Starting LXC Container... "
pct start $CTID
echo -e "${CM}${CL} \r"

alias lxc-cmd="lxc-attach -n $CTID --"

lxc-cmd bash -c "$(wget -qLO - https://raw.githubusercontent.com/tteck/Proxmox/unprev/homeassistant-install.sh)" || exit

IP=$(pct exec $CTID ip a s dev eth0 | sed -n '/inet / s/\// /p' | awk '{print $2}')

echo -e "${GN}Successfully created Home Assistant Container LXC to${CL} ${BL}$CTID${CL}.
${BL}Home Assistant${CL} is reachable by going to the following URL.

         ${BL}http://${IP}:8123${CL} \n"