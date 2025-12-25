#!/usr/bin/sh

NGX_VERSION='nginx-1.28.0'
wget https://nginx.org/download/$NGX_VERSION.tar.gz
tar -xf $NGX_VERSION.tar.gz
for PATCH_FILE in *.patch; { patch -d $NGX_VERSION/ -Np0 < $PATCH_FILE; }
