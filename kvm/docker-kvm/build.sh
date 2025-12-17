#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
source venv-full/bin/activate

auth_app=(api_auth config utils flask_app)
simplekvm_app=(config database flask_app main meta template utils vmmanager)
combined=($(for ip in "${simplekvm_app[@]}" "${auth_app[@]}"; do echo "${ip}"; done | sort -u))
for fn in ${combined[@]}; do
    cython ${fn}.py -o ${fn}.c
    gcc -fPIC -shared `python3-config --cflags --ldflags` ${fn}.c -o ${fn}.so
    strip ${fn}.so
    chmod 644 ${fn}.so
done
# # apt -y install libpython3.13 # runtime embed
cython --embed console.py -o console.c
gcc $(python3-config --includes) console.c $(python3-config --embed --libs) -o console
chmod 755 console
echo "copy file to /home/johnyin/disk/myvm/cloud-tpl/newkvm/simplekvm-amd64/docker/app/"
target=/home/johnyin/disk/myvm/cloud-tpl/newkvm/simplekvm-amd64
sudo cp console ${target}/docker/app/
for fn in ${simplekvm_app[@]}; do
    sudo cp $fn.so ${target}/docker/app/
done
for fn in ${auth_app[@]}; do
    sudo cp $fn.so ${target}/docker/auth/
done

sudo cp *.c arm64.rootfs/
sudo chroot arm64.rootfs /build.sh
echo "copy file to /home/johnyin/disk/myvm/cloud-tpl/newkvm/simplekvm-arm64/docker/app/"
target=/home/johnyin/disk/myvm/cloud-tpl/newkvm/simplekvm-arm64
sudo cp arm64.rootfs/console ${target}/docker/app/
for fn in ${simplekvm_app[@]}; do
    sudo cp arm64.rootfs/$fn.so ${target}/docker/app/
done
for fn in ${auth_app[@]}; do
    sudo cp arm64.rootfs/$fn.so ${target}/docker/auth/
done
