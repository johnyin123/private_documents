#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
source venv-full/bin/activate
# # apt -y install cython3
# apt -y install libpython3-dev:arm64 libvirt-dev:arm64

auth_app=(api_auth flask_app)
simplekvm_app=(config database flask_app main meta template utils vmmanager)
combined=($(for ip in "${simplekvm_app[@]}" "${auth_app[@]}"; do echo "${ip}"; done | sort -u))
for fn in ${combined[@]}; do
    cython -X language_level=3 ${fn}.py -o ${fn}.c
    gcc -fPIC -shared `python3-config --cflags --ldflags` ${fn}.c -o ${fn}.so
    strip ${fn}.so
    chmod 644 ${fn}.so
done
gcc console.c -lvirt -o console
# cython -X language_level=3 --embed console.py -o console.c
# apt -y install libpython3.13 # runtime embed
# apt -y install libpython3.13-dev:amd64
# gcc $(python3-config --includes) console.c $(python3-config --embed --libs) -o console
strip console
chmod 755 console
echo "copy file to /home/johnyin/disk/myvm/cloud-tpl/newkvm/simplekvm-amd64/docker/app/"
target=/home/johnyin/disk/myvm/cloud-tpl/docker-images/simplekvm-amd64
sudo cp console ${target}/docker/app/
for fn in ${simplekvm_app[@]}; do
    sudo cp $fn.so ${target}/docker/app/
done
for fn in ${auth_app[@]}; do
    sudo cp $fn.so ${target}/docker/auth/
done

for fn in ${combined[@]}; do
    aarch64-linux-gnu-gcc -fPIC -shared `aarch64-linux-gnu-python3-config --cflags --ldflags` ${fn}.c -o ${fn}.so
    aarch64-linux-gnu-strip ${fn}.so
    chmod 644 ${fn}.so
done
aarch64-linux-gnu-gcc console.c -lvirt -o console
aarch64-linux-gnu-strip console
chmod 755 console
echo "copy file to /home/johnyin/disk/myvm/cloud-tpl/newkvm/simplekvm-arm64/docker/app/"
target=/home/johnyin/disk/myvm/cloud-tpl/docker-images/simplekvm-arm64
sudo cp console ${target}/docker/app/
for fn in ${simplekvm_app[@]}; do
    sudo cp $fn.so ${target}/docker/app/
done
for fn in ${auth_app[@]}; do
    sudo cp $fn.so ${target}/docker/auth/
done
