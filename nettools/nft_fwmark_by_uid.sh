#!/usr/bin/env bash
# # fwmark by user
table=10
fwmark=777
user=johnyin
cat <<EOF
ip rule add fwmark ${fwmark} table ${table}
nft add table ip mangle
nft 'add chain ip mangle output { type route hook output priority -150; }'
nft add rule ip mangle output skuid $(id --user ${user}) counter mark set ${fwmark}
runuser -u root -- nc -v -n -z 8.8.8.8 53
runuser -u ${user} -- nc -v -n -z 8.8.8.8 53
EOF
