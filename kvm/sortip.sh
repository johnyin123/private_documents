#!/usr/bin/env bash
fname=${1:? must input}
cat ${fname} | sed "s/Co., Ltd.//g" | awk -F, '{ printf "%s\n", $13 }'| grep -v "^$" | sort -t. -k 3,3n -k 4,4n
