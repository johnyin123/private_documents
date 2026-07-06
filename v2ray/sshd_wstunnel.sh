#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
################################################################################
random() { shuf -i ${1:-1}-${2:-65535} -n ${3:-1}; }
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

SSH_PORT=${SSH_PORT:-60022}
SSH_VHOST=${SSH_VHOST:-microsoft.com}
NGX_SSH_WSPATH=${NGX_SSH_WSPATH:-"/api/ws_term"}
WST_SSH_PORT=${WST_SSH_PORT:-$(random 64000 64100)}
LOCAL_WST_PORT=${LOCAL_WST_PORT:-61122}
cat <<EOF
SSH_PORT       = ${SSH_PORT}
SSH_VHOST      = ${SSH_VHOST}
NGX_SSH_WSPATH = ${NGX_SSH_WSPATH}
WST_SSH_PORT   = ${WST_SSH_PORT}
LOCAL_WST_PORT = ${LOCAL_WST_PORT}
EOF
read -n 1 -p "Press any key continue ..." value

cat <<EOF >sshd_local_wstunnel.sh
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="\$(readlink -f "\$(dirname "\$0")")"

# NS_NAME=
PREFIX="${NGX_SSH_WSPATH}"
PREFIX="\${PREFIX/#\//}" # remove first /
systemd-run --unit wst-sshd \${NS_NAME:+-p NetworkNamespacePath=/run/netns/\${NS_NAME}} \\
\${DIRNAME}/wstunnel client --http-upgrade-path-prefix \${PREFIX} --local-to-remote tcp://127.0.0.1:${LOCAL_WST_PORT}:127.0.0.1:${SSH_PORT} --http-headers "Host: ${SSH_VHOST}" wss://RemoteHost:443
# ssh -p${LOCAL_WST_PORT} root@127.0.0.1
# ssh -o ProxyCommand="wstunnel client --http-upgrade-path-prefix ${NGX_SSH_WSPATH} --local-to-remote stdio://%h:%p --http-headers 'Host:${SSH_VHOST}' wss://RemoteHost:443" root@127.0.0.1
# ssh -o ProxyCommand="wstunnel client --http-upgrade-path-prefix ${NGX_SSH_WSPATH} --local-to-remote stdio://127.0.0.1:%p --http-headers 'Host:microsoft.com' wss://%h:443" root@srv -p ${SSH_PORT}
EOF
cat <<EOF > sshd_wstunnel_ngx.location
    location ${NGX_SSH_WSPATH} {
        if (\$request_method != "GET") { return 404; }
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass https://127.0.0.1:${WST_SSH_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_read_timeout 90m;
        proxy_send_timeout 90m;
    }
EOF
cat > sshd_wstunnel.service <<EOF
[Unit]
After=network.target
[Service]
Type=oneshot
DynamicUser=true
RemainAfterExit=yes
ExecStart=/bin/sh -c "./wstunnel server --restrict-to 127.0.0.1:${SSH_PORT} wss://127.0.0.1:${WST_SSH_PORT} &"
[Install]
WantedBy=multi-user.target
EOF

