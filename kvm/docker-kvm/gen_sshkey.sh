#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

function pkikey2sshpri() {
    local key=${1}
    chmod 600 ${key} && ssh-keygen -p -N "" -f ${key}
    ssh-keygen -f ${key} -y > ${key}.pub
}
cat ca.key > cacert
pkikey2sshpri cacert
cat clientkey.pem > id_rsa
pkikey2sshpri id_rsa
ssh-keygen -s cacert -I id_rsa -n simplekvm -V +520w id_rsa.pub
cat id_rsa-cert.pub > id_rsa.pub
cat <<'EOF'
sed --quiet -i.orig -E \
    -e '/^\s*(TrustedUserCAKeys)\s.*/!p' \
    -e '$aTrustedUserCAKeys /etc/ssh/cacert.pub' \
    /etc/ssh/sshd_config
EOF
