#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2024-02-01T13:50:00+08:00]:zabbix_jsonrpc.sh")
################################################################################
## 111649
curl -X POST -H 'Content-Type:application/json' \
    -d '{
    "jsonrpc":"2.0", 
    "method":"history.get",
    "params":{
        "output":"extend",
        "history":0,
        "itemids":"111515",
        "sortfield": "clock",
        "sortorder": "DESC",
        "limit": 100 
    },
    "id":1,
    "auth":"53fa7d429f085fcba21b796505e848426ae5fa6a132d62041479c0a507739de0"
    }' \
    http://172.16.0.222:8080/api_jsonrpc.php | jq .
