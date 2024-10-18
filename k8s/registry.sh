#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("ca28dd2[2023-08-14T14:04:01+08:00]:registry.sh")
################################################################################
cat <<EOF
https://github.com/distribution/distribution/releases/download/v2.8.2/registry_2.8.2_linux_amd64.tar.gz
apt -y install docker-registry apache2-utils
# list images
curl -X GET -u'admin:password' http://localhost:5000/v2/_catalog
# list image tag
curl -X GET -u'admin:password' http://localhost:5000/v2/${image}/tags/list
常用操作
$ docker tag myrepos/myimage:latest localhost:5000/myrepos/myimage:2.1
$ docker push localhost:5000/myrepos/myimage:2.1
$ docker pull localhost:5000/myrepos/myimage:2.1
这里要注意的是不管push还是pull，必须使用<registryserver>:<port>/repository的格式，而不能使用本地的格式，所以通常每次push和pull都会有两个命令，一个是改名，然后再push和pull。
EOF
password=password
sed -i "s|path\s*:.*|path: /etc/docker/registry/registry.password|g" /etc/docker/registry/config.yml
htpasswd -Bbn admin password > /etc/docker/registry/registry.password
echo "add <registry_addr>:5000 in docker daemon.json insecure-registries: [ ip, ip:port ]"
docker login --username admin --password-stdin localhost:5000
mkdir -p $(cat /etc/docker/registry/config.yml | sed --quiet -E 's/\s*rootdirectory\s*:\s*(.*)/\1/p')
chown docker-registry:docker-registry -R $(cat /etc/docker/registry/config.yml | sed --quiet -E 's/\s*rootdirectory\s*:\s*(.*)/\1/p')
cat <<EOF
storage:
  s3:
    region: us-east-1
    bucket: public
    accesskey: admin
    secretkey: tsd@2023
    regionendpoint: http://172.16.16.2
    secure: false

# radosgw-admin user create --uid="nak3" --display-name="test admin" --email=nak3@example.com --access_key="testkey" --secret="testsecret"
# radosgw-admin subuser create --uid="nak3" --subuser="nak3:swift" --access_key="testkey" --secret="testsecret" --access=full
# # create a bucket
# swift -V 1.0 -A http://knakayam-ceph-c2.example.com/auth/v1 -U nak3:swift -K testsecret post docker-registry
# # touch test-file
# swift -V 1.0 -A http://knakayam-ceph-c2.example.com/auth/v1 -U nak3:swift -K testsecret upload docker-registry test-file
# swift -V 1.0 -A http://knakayam-ceph-c2.example.com/auth/v1 -U nak3:swift  -K testsecret list docker-registry
storage:
  cache:
    blobdescriptor: inmemory
  swift:
    username: nak3:swift
    password: testsecret
    authurl: http://knakayam-ceph-c2.example.com/auth/v1.0
    insecureskipverify: false
    container: docker-registry
    rootdirectory: /registry
EOF
cat <<'EOF'
# storage:
#    filesystem:
#      rootdirectory: /registry
#    delete:
#      enabled: true
#    readonly:
#      enabled: false

repo=http://192.168.168.250
for pkg in $(curl -sk -X GET ${repo}/v2/_catalog | jq -r .repositories[]); do
    curl -sk -X GET ${repo}/v2/${pkg}/tags/list | jq -r .tags[] | sed "s|^|${pkg}:|g"
done

mirror=registry.aliyuncs.com/google_containers
for img in $(kubeadm config images list --kubernetes-version=v1.21.7 --image-repository=${mirror})
do
    target_img=192.168.168.250/google_containers/${img##*/}
    ctr -n k8s.io image pull ${img} --all-platforms
    ctr -n k8s.io image tag ${img} ${target_img}
    ctr -n k8s.io image push ${target_img} --platform amd64 --platform arm64 --plain-http
done
EOF
