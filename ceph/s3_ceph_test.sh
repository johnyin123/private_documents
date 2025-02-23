#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("77566a6[2024-10-24T09:22:46+08:00]:s3_ceph_test.sh")
################################################################################
FILTER_CMD="cat"
LOGFILE=
################################################################################
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -a|--access_key  *   access_key
        -s|--secret_key  *   secret_key
        -u|--url         *   s3 url
        -e|--expire <int>    presigned url expire seconds, default 600
        --upload             presigned url upload, default is download
        --delete             presigned url delete
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
       # add user
        radosgw-admin user create --uid=admin --display-name=admin --access_key=admin --secret=123456
        radosgw-admin caps add --uid=admin --caps="users=read, write"
        radosgw-admin caps add --uid=admin --caps="usage=read, write"
       create bucket: ${SCRIPTNAME} -a key -s key -u url <bucket>
       upload:        ${SCRIPTNAME} -a key -s key -u url <localfile> name@bucket
                      curl -X PUT -T <file> <presigned_url>
       download:      ${SCRIPTNAME} -a key -s key -u url name@bucket <localfile> 
                      curl <presigned_url> <output>
       presigned upload:
                      ${SCRIPTNAME} -a key -s key -u url --upload name@bucket
       presigned delete:
                      ${SCRIPTNAME} -a key -s key -u url --delete name@bucket
EOF
    exit 1
}

create_bucket() {
    local host=$1
    local bucket=$2
    local secret_key=$3
    local access_key=$4

    local uri="/${bucket}"
    local date=$(env LC_ALL=C date +"%a, %d %b %Y %T %z" -u)
    local str="PUT\n\n\n${date}\n${uri}"
    local signature=$(echo -en "${str}" | openssl sha1 -hmac "${secret_key}" -binary | base64)
    local cmd=("curl" "-s" "--fail" "-w" '%{http_code}')
    cmd+=("-X" "PUT")
    cmd+=("-H" "Date: ${date}")
    cmd+=("-H" "Authorization: AWS ${access_key}:${signature}")
    cmd+=("${host}${uri}")
    local status=$("${cmd[@]}")
    echo "return $status"
}

put() {
    local source=$1
    local host=$2
    local bucket=$3
    local target=$4
    local secret_key=$5
    local access_key=$6

    local content_type=$(file ${source} --mime-type | awk '{print $2}')
    local uri="/${bucket}/${target}"
    str_starts "${target}" "/" && uri="/${bucket}${target}"
    local date=$(env LC_ALL=C date +"%a, %d %b %Y %T %z" -u)
    local str="PUT\n\n${content_type}\n${date}\n${uri}"
    local signature=$(echo -en "${str}" | openssl sha1 -hmac "${secret_key}" -binary | base64)
    local cmd=("curl" "-s" "--fail" "-w" '%{http_code}')
    cmd+=("-X" "PUT")
    cmd+=("-T" "${source}")
    cmd+=("-H" "Content-Type: ${content_type}")
    cmd+=("-H" "Date: ${date}")
    cmd+=("-H" "Authorization: AWS ${access_key}:${signature}")
    cmd+=("${host}${uri}")
    local status=$("${cmd[@]}")
    echo "return $status"
}

get() {
    local host=$1
    local bucket=$2
    local source=$3
    local target=$4
    local secret_key=$5
    local access_key=$6

    local uri="/${bucket}/${source}"
    str_starts "${source}" "/" && uri="/${bucket}${source}"
    local date=$(env LC_ALL=C date +"%a, %d %b %Y %T %z" -u)
    local str="GET\n\n\n${date}\n${uri}"
    local signature=$(echo -en "${str}" | openssl sha1 -hmac "${secret_key}" -binary | base64)
    local cmd=("curl" "-s" "--fail" "-w" '%{http_code}')
    cmd+=("-o" "${target}")
    cmd+=("-X" "GET")
    cmd+=("-H" "Date: ${date}")
    cmd+=("-H" "Authorization: AWS ${access_key}:${signature}")
    cmd+=("${host}${uri}")
    local status=$("${cmd[@]}")
    echo "return $status"
}

presigned_url() {
    local host=$1
    local bucket=$2
    local source=$3
    local expire=$4
    local secret_key=$5
    local access_key=$6
    local method=${7:-GET}
    local uri="/${bucket}/${source}"
    local date=$(date -d "+${expire} second" +%s)
    local str="${method}\n\n\n${date}\n${uri}"
    local signature=$(echo -en "${str}" | openssl sha1 -hmac "${secret_key}" -binary | base64)
    echo -n "${host}${uri}?AWSAccessKeyId=${access_key}&Expires=${date}&Signature=$(urlencode ${signature})"
}

main() {
    local access_key="" secret_key="" s3_host="" srcfile="" bucket="" tgtfile="" expire=600 method=GET
    local opt_short="a:s:u:e:"
    local opt_long="access_key:,secret_key:,url:,expire:,upload,delete,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -a | --access_key) shift; access_key=${1}; shift;;
            -s | --secret_key) shift; secret_key=${1}; shift;;
            -u | --url)        shift; s3_host=${1}; shift;;
            -e | --expire)     shift; expire=${1}; shift;;
            --upload)          shift; method=PUT;; 
            --delete)          shift; method=DELETE;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [ -z "${s3_host}" ] || [ -z "${secret_key}" ] || [ -z "${access_key}" ] || {
        if [[ " $@" =~ .*?[[:space:]]([^[:space:]]+)@([^[:space:]]*)[[:space:]]+([^[:space:]]+) ]] ; then
            # download file from S3 Service
            srcfile=${BASH_REMATCH[1]}
            bucket=${BASH_REMATCH[2]}
            tgtfile=${BASH_REMATCH[3]}
            get "${s3_host}" ${bucket} "${srcfile}" ${tgtfile} ${secret_key} ${access_key}
        elif [[ " $@" =~ .*?[[:space:]]([^[:space:]]+)[[:space:]]+([^[:space:]]+)@([^[:space:]]*) ]] ; then
            # upload file to S3 Service
            srcfile=${BASH_REMATCH[1]}
            bucket=${BASH_REMATCH[3]}
            tgtfile=${BASH_REMATCH[2]}
            put "${srcfile}" "${s3_host}" ${bucket} ${tgtfile} ${secret_key} ${access_key}
        elif [[ " $@" =~ .*?[[:space:]]([^[:space:]]+)@([^[:space:]]*)[[:space:]]* ]] ; then
            srcfile=${BASH_REMATCH[1]}
            bucket=${BASH_REMATCH[2]}
            cmd=("curl" "-s" "--fail" "-w" '%{http_code}')
            cmd+=("-X" "${method}")
            echo -n "${cmd[@]} '"
            presigned_url "${s3_host}" ${bucket} "${srcfile}" "${expire}" ${secret_key} ${access_key} ${method}
            echo "'"
        else
            bucket=${1:-}
            [ -z ${bucket} ] && usage "bucket name"
            create_bucket "${s3_host}" ${bucket} ${secret_key} ${access_key}
        fi
        return 0
    }
    usage "url/secret_key/access_key"
    return 1
}
main "$@"
