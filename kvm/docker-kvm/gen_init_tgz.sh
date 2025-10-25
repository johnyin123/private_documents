#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
################################################################################
INIT_TPL=(meta/meta-data.tpl meta/user-data.tpl devices/disk.file.tpl devices/disk.file.action devices/net.br-ext.tpl devices/cdrom.null.tpl domains/domain.tpl)
INIT_DBS=(golds.json iso.json)

SOURCE_DIR=${1:?$(echo "input SOURCE DIR"; exit 1;)}

tmp_dir=$(mktemp -d "/tmp/simplekvm-init-$(date +'%Y%m%d%H%M%S')-XXXXXXXXXX")
cat <<'EOF' > ${tmp_dir}/golds.json
[{"name":"","arch":"x86_64","uri":"","size":1,"desc":"数据盘"},{"name":"","arch":"aarch64","uri":"","size":1,"desc":"数据盘"}]
EOF
cat <<'EOF' > ${tmp_dir}/iso.json
[{"name":"","uri":"","desc":"MetaData ISO"}]
EOF
for fn in ${INIT_FILES[@]}; do
    target=${tmp_dir}/${fn}
    mkdir -p $(dirname "${target}") && cat "${SOURCE_DIR}/${fn}" > "${target}"
done
