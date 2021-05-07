#!/usr/bin/env bash

CN=myca.kvm

echo "GEN CA"
certtool --generate-privkey > cakey.pem
cat <<EOF > ca.info
cn = ${CN}
ca
cert_signing_key
EOF
certtool --generate-self-signed --load-privkey cakey.pem --template ca.info --outfile cacert.pem
cp cacert.pem /etc/pki/CA/

echo "GEN Server key"
SRV_IP=10.0.100.2
certtool --generate-privkey > serverkey.pem

cat <<EOF > server.info
organization = ${CN}
cn = ${CN}
dns_name = ${CN}
ip_address = ${SRV_IP}
tls_www_server
encryption_key
signing_key
EOF

certtool --generate-certificate --load-privkey serverkey.pem \
  --load-ca-certificate ./cacert.pem --load-ca-privkey ./cakey.pem \
  --template server.info --outfile servercert.pem

mkdir -p $HOME/.pki/libvirt/ && cp serverkey.pem servercert.pem $HOME/.pki/libvirt/
sed -i "s/^#\s*LIBVIRTD_ARGS=.*/LIBVIRTD_ARGS=\"--listen\"/g" /etc/sysconfig/libvirtd 


echo "GEN Client key"
certtool --generate-privkey > clientkey.pem

cat <<EOF > client.info
country = COUNTRY
state = STATE
locality = LOCALITY
organization = ${CN}
cn = ${CN}
tls_www_client
encryption_key
signing_key
EOF

certtool --generate-certificate --load-privkey clientkey.pem \
  --load-ca-certificate ./cacert.pem --load-ca-privkey ./cakey.pem \
  --template client.info --outfile clientcert.pem

cat <<"EOF"
on client do:
mkdir -p $HOME/.pki/libvirt/ && cp clientkey.pem clientcert.pem $HOME/.pki/libvirt/
EOF
