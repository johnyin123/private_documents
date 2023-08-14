#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("7ce2548[2023-08-11T13:08:42+08:00]:registry.sh")
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
cat <<'EOF_SHELL'
#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
mkdir -p "${DIRNAME}/data"
cat <<EOF > "${DIRNAME}/config.yml"
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: ${DIRNAME}/data
  delete:
    enabled: true
      #  readonly:
      #    enabled: false
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
EOF
nohup "${DIRNAME}/registry" serve "${DIRNAME}/config.yml"  &>/dev/null &
EOF_SHELL
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
upstream docker-registry {
    server 127.0.0.1:5000;
}
map $upstream_http_docker_distribution_api_version $docker_distribution_api_version {
    '' 'registry/2.0';
}
server {
    listen 80;
    listen 443 ssl;
    server_name _;
    ssl_certificate /etc/nginx/ssl/k8s-tsd.pem;
    ssl_certificate_key /etc/nginx/ssl/k8s-tsd.key;
    location /v2/ {
        if ($http_user_agent ~ "^(docker\/1\.(3|4|5(?!\.[0-9]-dev))|Go ).*$" ) {
            return 404;
        }
        add_header 'Docker-Distribution-Api-Version' $docker_distribution_api_version always;
        proxy_pass                         http://docker-registry;
        proxy_set_header Host              $http_host;   # required for docker client's sake
        proxy_set_header X-Real-IP         $remote_addr; # pass on real client's IP
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout                 900;
    }
    location / {
        root /var/www;
    }
}
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
