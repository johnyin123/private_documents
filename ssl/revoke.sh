cadir=./myCA
cat<<EOSSL>ssl.conf 
[ ca ]
default_ca	= CA_default		# The default ca section
[ CA_default ]
certificate	= ${cadir}/ca.pem 	# The CA certificate
private_key	= ${cadir}/ca.key    # The private key
database	= ${cadir}/index.txt	# database index file.
default_md  = default
[ server_cert ]
crlDistributionPoints = URI:http://example.com/intermediate.crl.pem
EOSSL
touch ${cadir}/index.txt 
echo openssl ca -config ssl.conf -revoke client.pem -keyfile ca.key -cert ca.pem
echo openssl ca -config ssl.conf -gencrl -keyfile ca.key -cert ca.pem -out mycrl.crl -crldays +100
