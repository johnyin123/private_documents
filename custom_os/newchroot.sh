#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}

ROOTFS=${1:?rootfs need input}

systemd-nspawn --network-veth --network-bridge=br-ext -D ${ROOTFS}
