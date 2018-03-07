#!/bin/bash
dirname="$(dirname "$(readlink -e "$0")")"

cd ${dirname}/openssl-1.0.2n
./config no-shared
make
cd ${dirname}/gvpe-3.0
./configure --prefix= --datarootdir=/usr/share --with-openssl-include=${dirname}/openssl-1.0.2n/include/ --with-openssl-lib=${dirname}/openssl-1.0.2n/ --enable-static-daemon
make
mkdir -p ${dirname}/target
make install DESTDIR=${dirname}/target

mkdir -p ${dirname}/target/usr/lib/systemd/system/
cat > ${dirname}/target/usr/lib/systemd/system/gvpe@.service <<EOF
[Unit]
Description=gvpe service for node %i
After=network.target

[Service]
Type=forking
PIDFile=/var/run/gvpe.pid
ExecStart=/sbin/gvpe %i

[Install]
WantedBy=multi-user.target
EOF
cd ${dirname}/
fpm -s dir -t rpm -C ${dirname}/target --name gvpe-johnyin --version 3.0 --iteration 1 --depends zlib --description "gvpe vpn which openssl 1.0.2n static link"
fpm -s dir -t deb -C ${dirname}/target --name gvpe-johnyin --version 3.0 --iteration 1 --depends zlib1g --description "gvpe vpn which openssl 1.0.2n static link"

