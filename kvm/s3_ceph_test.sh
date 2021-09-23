#!/bin/bash

put() {
    local source=$1
    local host=$2
    local bucket=$3
    local target=$4
    local secret_key=$5
    local access_key=$6

    local content_type=$(file ${source} --mime-type | awk '{print $2}')
    local uri="/${bucket}/${target}"
    local date=$(env LC_ALL=C date +"%a, %d %b %Y %T %z" -u)
    local str="PUT\n\n${content_type}\n${date}\n${uri}"
    local signature=$(echo -en "${str}" | openssl sha1 -hmac "${secret_key}" -binary | base64)
    local cmd=("curl" "-s")
    cmd+=("-X" "PUT")
    cmd+=("-T" "${source}")
    cmd+=("-H" "Content-Type: ${content_type}")
    cmd+=("-H" "Date: ${date}")
    cmd+=("-H" "Authorization: AWS ${access_key}:${signature}")
    cmd+=("${host}${uri}")
    "${cmd[@]}"
}

get() {
    local host=$1
    local bucket=$2
    local source=$3
    local target=$4
    local secret_key=$5
    local access_key=$6

    local uri="/${bucket}/${source}"
    local date=$(env LC_ALL=C date +"%a, %d %b %Y %T %z" -u)
    local str="GET\n\n\n${date}\n${uri}"
    local signature=$(echo -en "${str}" | openssl sha1 -hmac "${secret_key}" -binary | base64)
    local cmd=("curl" "-s")
    cmd+=("-o" "${target}")
    cmd+=("-X" "GET")
    cmd+=("-H" "Date: ${date}")
    cmd+=("-H" "Authorization: AWS ${access_key}:${signature}")
    cmd+=("${host}${uri}")
    "${cmd[@]}"
}

access_key='AIOCOC1SP6WB4JLD3Q2U'
secret_key='lVEqs4cDudYvrJDrDOxxAGMRekmLR9KHCAjBDBc7'
s3_host=http://192.168.168.101

# switch action
if [[ " $@" =~ .*?[[:space:]]([^[:space:]]+)@([^[:space:]]*)[[:space:]]+([^[:space:]-]+) ]] ; then
  # download file from S3 Service
  SOURCE=${BASH_REMATCH[1]}
  BUCKET=${BASH_REMATCH[2]}
  TARGET=${BASH_REMATCH[3]}
  get "${s3_host}" ${BUCKET} "${SOURCE}" ${TARGET} $secret_key $access_key
elif [[ " $@" =~ .*?[[:space:]]([^[:space:]]+)[[:space:]]+([^[:space:]]+)@([^[:space:]]*) ]] ; then
  # upload file to S3 Service
  SOURCE=${BASH_REMATCH[1]}
  BUCKET=${BASH_REMATCH[3]}
  TARGET=${BASH_REMATCH[2]}
  put "${SOURCE}" "${s3_host}" ${BUCKET} ${TARGET} $secret_key $access_key
fi
#$0 source target@bucket  #upload
#$0 source@bucket target  #download
