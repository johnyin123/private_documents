cat <<EOF > ca-config.json
{
    "signing": {
        "default": { "expiry": "8760h" },
        "profiles": {
            "simplekvm": {
                "expiry": "87600h",
                "usages": [ "signing", "key encipherment", "server auth", "client auth" ]
            }
        }
    }
}
EOF
# ./cfssl print-defaults csr
cat <<EOF | cfssl gencert -initca /dev/stdin | cfssljson -bare ca
{
    "ca": { "expiry": "131400h" },
    "CN": "simplekvm ca",
    "key": { "algo": "rsa", "size": 2048 },
    "names": [ { "C": "CN", "ST": "LN", "L": "SY" } ]
}
EOF
cat <<EOF | cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=simplekvm /dev/stdin | cfssljson -bare server 
{
    "CN": "libvirtd",
    "hosts": [ "192.168.1.226", "kvm01.local" ],
    "key": { "algo": "rsa", "size": 2048 },
    "names": [ { "C": "CN", "ST": "LN", "L": "SY" } ]
}
EOF
openssl x509 -text -noout -in server.pem | grep -iE 'Not After|DNS:| IP Address:'

cat <<EOF | cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=simplekvm /dev/stdin | cfssljson -bare simplekvm
{
    "CN": "simplekvm",
    "hosts": [ "vmm.registry.local" ],
    "key": { "algo": "rsa", "size": 2048 },
    "names": [ { "C": "CN", "ST": "LN", "L": "SY" } ]
}
EOF
openssl x509 -text -noout -in simplekvm.pem | grep -iE 'Not After|DNS:| IP Address:'
