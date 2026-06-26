#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("8199ce2d[2026-06-26T13:47:00+08:00]:wg_via_v2ray.sh")
################################################################################
FILTER_CMD="cat"
LOGFILE=
################################################################################
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

cat <<EOF
  "rules": [
    { "type": "field", "inboundTag": ["cli_in_udp"], "outboundTag": "srv_out_udp" }
  ]
### server
  "outbounds": [
    { "tag": "srv_out_udp", "protocol": "freedom", "settings": { "redirect": "127.0.0.1:51820" } }
  ]
[Interface]
PrivateKey = SERVER_PRIVATE_KEY
Address = 10.0.0.1/24
ListenPort = 51820

### client
  "inbounds": [
    { "tag": "cli_in_udp", "listen": "127.0.0.1", "port": 10808, "protocol": "socks", "settings": { "udp": true } }
  ]

[Peer]
PublicKey = SERVER_PUBLIC_KEY
# Routes traffic to the local V2Ray proxy port
Endpoint = 127.0.0.1:10808
AllowedIPs = 0.0.0.0/0
EOF
