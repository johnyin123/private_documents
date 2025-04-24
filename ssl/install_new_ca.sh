#!/usr/bin/env bash
echo 'convert: openssl x509 -in input.ca.cer -out out.pem'
CA=${1:?CA FILENAME??}
mkdir -p /usr/share/ca-certificates/custom-ca
cp ${CA} /usr/share/ca-certificates/custom-ca/
echo "custom-ca/${CA}" >> /etc/ca-certificates.conf
update-ca-certificates
cat <<EOF
# # centos
# ln -s .... /etc/ssl/certs/
EOF
