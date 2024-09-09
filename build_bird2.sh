#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}

echo "https://bird.network.cz/download/bird-doc-2.0.12.tar.gz"
PKG=rpm
BIRD2_VER=2.0.12
export DESTDIR=${DIRNAME}/out
mkdir -p ${DESTDIR}
CFLAGS="-static -static-libgcc" LDFLAGS="-static" ./configure --prefix=/usr --sysconfdir=/etc/bird --runstatedir=/run --disable-client
make
make install

mkdir -p ${DESTDIR}/etc/bird && cat <<'EOF' > ${DESTDIR}/etc/bird/envvars 
BIRD_RUN_USER=bird
BIRD_RUN_GROUP=bird
#BIRD_ARGS=
EOF
mkdir -p ${DESTDIR}/lib/systemd/system && cat <<'EOF' > ${DESTDIR}/lib/systemd/system/bird.service
[Unit]
Description=BIRD Internet Routing Daemon
After=network.target network-online.target

[Service]
EnvironmentFile=/etc/bird/envvars
ExecStartPre=/usr/lib/bird/prepare-environment
ExecStartPre=/usr/sbin/bird -p
ExecReload=/usr/sbin/birdc configure
ExecStart=/usr/sbin/bird -f -u $BIRD_RUN_USER -g $BIRD_RUN_GROUP $BIRD_ARGS
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF

mkdir -p ${DESTDIR}/usr/lib/bird/ && cat <<'EOF' > ${DESTDIR}/usr/lib/bird/prepare-environment
#!/bin/sh

set -eu

BIRD_RUN_DIR=/run/bird
. /etc/bird/envvars


mkdir --parents "$BIRD_RUN_DIR";

if [ -n "$BIRD_RUN_USER" ]; then
    if ! getent passwd $BIRD_RUN_USER >/dev/null; then
	echo "Configured user '$BIRD_RUN_USER' doesn't exist."
	exit 1
    fi
fi

if [ -n "$BIRD_RUN_GROUP" ]; then
    if ! getent group $BIRD_RUN_GROUP >/dev/null; then
	echo "Configured group '$BIRD_RUN_GROUP' doesn't exist."
	exit 1
    fi
fi

chown --silent "$BIRD_RUN_USER:$BIRD_RUN_GROUP" "$BIRD_RUN_DIR"
chmod 775 "$BIRD_RUN_DIR"

:
EOF
chmod 755 ${DESTDIR}/usr/lib/bird/prepare-environment

source ${DESTDIR}/etc/bird/envvars
INST_SCRIPT=$(mktemp)
UNINST_SCRIPT=$(mktemp)
echo "adduser --system --no-create-home --home /run/bird ${BIRD_RUN_USER} || :" > ${INST_SCRIPT}
echo "userdel ${BIRD_RUN_USER} || :" > ${UNINST_SCRIPT}
fpm --package ${DIRNAME}/ -s dir -t ${PKG} -C ${DESTDIR} --name bird2_johnyin --version $(echo ${BIRD2_VER}) --iteration 0.9 --description "bird2 ospf/bgp" --after-install ${INST_SCRIPT} --after-remove ${UNINST_SCRIPT} .
