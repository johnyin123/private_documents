#!/bin/bash

cat << EOF |
[ { "foo": 42, "something": "else" }, { "foo": 12, "more": { "age": 12} } ]
EOF
jq -c -r '.[]' | while read -r json
do 
	jq -r '.foo' <<< $json | while read -r foo
	do
        addTen=$(( "$foo" + 10))
        jq --arg addTen "$addTen" '.properties.addTen = ($addTen|tonumber)' <<< $json
	done
done | jq -s

# jq '.vms[]| select(.addr[0] != "")'| jq .addr[0] | sort -t. -k 3,3n -k 4,4n^C
# jq '.vms[]| select(.addr[0] == "172.16.6.1/21")' | jq .addr[0] | sort -t. -k 3,3n -k 4,4n
