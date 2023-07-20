#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("initver[2023-07-20T12:56:22+08:00]:registry.sh")
################################################################################
cat <<EOF
https://github.com/distribution/distribution/releases/download/v2.8.2/registry_2.8.2_linux_amd64.tar.gz
apt -y install docker-registry
# list images
curl -X GET -u'user1:password' http://localhost:5000/v2/_catalog
# list image tag
curl -X GET -u'user1:password' http://localhost:5000/v2/${image}/tags/list
常用操作
$ docker tag myrepos/myimage:latest localhost:5000/myrepos/myimage:2.1
$ docker push  localhost:5000/myrepos/myimage:2.1
$ docker pull localhost:5000/myrepos/myimage:2.1
这里要注意的是不管push还是pull，必须使用<registryserver>:<port>/repository的格式，而不能使用本地的格式，所以通常每次push和pull都会有两个命令，一个是改名，然后再push和pull。
EOF
password=password
sed -i "s|path\s*:.*|path: /etc/docker/registry/registry.password|g" /etc/docker/registry/config.yml
printf "admin:$(openssl passwd -apr1 ${password})\n" > /etc/docker/registry/registry.password
docker login --username admin --password-stdin localhost:5000
