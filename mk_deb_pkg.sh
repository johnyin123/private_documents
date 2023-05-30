#!/usr/bin/env bash
BIN=${1:?need bin}
PKG=${2:?need pkg name}
mkdir -p ${PKG}/usr/bin/ ${PKG}/DEBIAN
cp ${BIN} ${PKG}/usr/bin/
cat <<EOF > ${PKG}/DEBIAN/control
Package: ${PKG}
Version: 1.0
Section: custom
Priority: optional
Architecture: all
Essential: no
Installed-Size: 1024
Maintainer: sample.org
Description: desc message here 
EOF
dpkg-deb --build ${PKG}
