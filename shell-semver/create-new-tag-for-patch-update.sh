#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

NEW_TAG=$($SCRIPT_DIR/increment_version.sh -p $LATEST_TAG)
