#!/usr/bin/env bash
fname=${1:? must input}
tail -n +2  ${fname} | sed "s/Co., Ltd.//g" | awk -F, '{ printf "%s\n", $13 }'| grep -v "^$" | sort -t. -k 3,3n -k 4,4n
tail -n +2  ${fname} | awk -F, '{print $2}' | sort -t. -k 3,3n -k 4,4n | uniq --count
