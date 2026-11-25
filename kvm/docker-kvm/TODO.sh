#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
VENV=${DIRNAME}/venv

# python3 -m venv venv
# pip install libvirt-python==11.3.0 gunicorn Flask pycdlib websockify ldap3 pyjwt[crypto] requests etcd3gw
# pip install supervisor

username=$(id -un)
USER_HOME=/home/${username}

ALL_PRIKEY=${USER_HOME}/.pki/libvirt/clientkey.pem
ALL_PUBKEY=${USER_HOME}/.pki/libvirt/clientcert.pem
JWT_PRIKEY=${ALL_PRIKEY}
JWT_PUBKEY=${USER_HOME}/pubkey.pem

token_dir=/dev/shm/simplekvm/token
target=${DIRNAME}/nginx/conf
# 1,$ s/\${target}\/nginx/${target}/g
sed -i "s|/etc/nginx|${USER_HOME}/nginx/conf|g" ${target}/http-enabled/*
# sed -i -e '/include\s.*error_page.inc\s*;/{r error_page.inc' -e 'd}'
mkdir -p ${target}/ssl
rm -f ${target}/ssl/simplekvm.pem && ln -s ${ALL_PUBKEY} ${target}/ssl/simplekvm.pem
rm -f ${target}/ssl/simplekvm.key && ln -s ${ALL_PRIKEY} ${target}/ssl/simplekvm.key
rm -f ${target}/ssl/pubkey.pem    && ln -s ${JWT_PUBKEY} ${target}/ssl/pubkey.pem

cat <<EODOC > supervisord.conf
[supervisord]
nodaemon=true
user=root
environment=PATH="${VENV:+${VENV}/bin:}%(ENV_PATH)s"
logfile=/dev/stdout
logfile_maxbytes=0
pidfile=/var/run/supervisord.pid

[program:nginx]
directory=${USER_HOME}/nginx
command=${USER_HOME}/nginx/nginx -g "daemon off;"
autostart=true
autorestart=true
startretries=10
startsecs=1
user=root
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:websockify]
command=websockify --token-plugin TokenFile --token-source ${token_dir} 127.0.0.1:6800
autostart=true
autorestart=true
startretries=10
startsecs=1
user=${username}
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:api_auth]
umask=0022
environment=JWT_PUBKEY=${JWT_PUBKEY},JWT_PRIKEY=${JWT_PRIKEY}
command=gunicorn --chdir ${USER_HOME}/app -b 127.0.0.1:16000 --max-requests 50000 --preload --workers=1 --threads=2 --access-logformat 'JWT %%(r)s %%(s)s %%(M)sms len=%%(B)s' --access-logfile='-' 'api_auth:create_app()'
autostart=true
autorestart=true
startretries=5
user=${username}
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:simplekvm]
umask=0022
environment=HOME="${USER_HOME}",TOKEN_DIR="${token_dir}"
directory=${USER_HOME}/app
command=gunicorn -b 127.0.0.1:5009 --max-requests 50000 --preload --workers=1 --threads=2 --access-logformat 'API %%(r)s %%(s)s %%(M)sms len=%%(B)s' --access-logfile='-' 'main:create_app()'
autostart=true
autorestart=true
startretries=10
startsecs=1
user=${username}
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
EODOC

cat <<EOF
NS_NAME=ns-name
# systemd-run --user --unit simple-kvm \
source ${VENV}/bin/activate
systemd-run --unit simple-kvm \
  \${NS_NAME:+-p NetworkNamespacePath=/run/netns/\${NS_NAME}} \
  \${NS_NAME:+-p BindPaths=/etc/netns/\${NS_NAME}/resolv.conf:/etc/resolv.conf} \
  \${NS_NAME:+-p BindPaths=/etc/netns/\${NS_NAME}/hosts:/etc/hosts} \
  --property=UMask=0022 \
  --property=BindPaths=${DIRNAME}:${USER_HOME} \
  ${DIRNAME}/entrypoint.sh supervisord -n -c ${USER_HOME}/supervisord.conf
EOF

cat <<EOF
with subprocess.Popen(..., start_new_session=True) as proc:
  #isolates process group so child processes also die
  os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
EOF
