#!/usr/bin/env bash
netns_exists() {
    local ns_name="$1"
    # Check if a namespace named $ns_name exists.
    # Note: Namespaces with a veth pair are listed with '(id: 0)' (or something). We need to remove this before lookin
    # /var/run/netns/${ns_name} ?? exists
    ip netns list | sed 's/ *(id: [0-9]\+)$//' | grep --quiet --fixed-string --line-regexp "${ns_name}"
}
netns_exists ns-v2ray || sudo systemctl start netns@ns-v2ray
export http_proxy=http://127.0.0.1:8080
export https_proxy=http://127.0.0.1:8080
export no_proxy="localhost, 127.0.0.1, 192.168.0.0/16"
sudo --preserve-env ip netns exec ns-v2ray su johnyin -c "google-chrome"
cat <<EOF
sudo --preserve-env ip netns exec ns-v2ray su johnyin
EOF
