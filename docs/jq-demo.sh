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
