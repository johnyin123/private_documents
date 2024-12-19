#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("initver[2024-12-19T13:44:36+08:00]:mini.sh")
################################################################################
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
main() {
    log "LOGFILE=logfile FILTER_CMD=cat ${0}"
    exec > >(${FILTER_CMD:-sed '/^\s*#/d'} | tee ${LOGFILE:+-i ${LOGFILE}})
}
main "$@"
