#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("playbook_init.sh - be6cd99 - 2021-04-27T14:31:08+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
main() {
    local pbm=${1:-demo}
    [[ -r "${DIRNAME}/site.yml" ]] && {
        echo "- import_playbook: ${pbm}.yml" >> ${DIRNAME}/site.yml
    } || {
        cat > ${DIRNAME}/site.yml <<EOF
#!/usr/bin/env ansible-playbook
---
- import_playbook: ${pbm}.yml
EOF
    chmod 755 ${DIRNAME}/site.yml
    }

    [[ -r "${DIRNAME}/hosts" ]] || {
        cat > ${DIRNAME}/hosts <<EOF
[all:vars]
ansible_connection=ssh
#ssh or paramiko
ansible_user=root
#ansible_ssh_pass=password

[local] 
127.0.0.1:60022
EOF
    }
    [[ -r "${DIRNAME}/${pbm}.yml" ]] || {
        cat > ${DIRNAME}/${pbm}.yml <<EOF
---
# ansible-playbook ${pbm}.yml -i hosts -e 'env=local'
- name: main playbook
  hosts: "{{ env }}"

  roles:
    - ${pbm}
...
EOF
    }
    mkdir -p group_vars
    [[ -r "${DIRNAME}/group_vars/${pbm}" ]] || {
        cat > ${DIRNAME}/group_vars/${pbm} <<EOF
#http_port: 8080
#https_port: 8443
EOF
    }
    [[ -d "${DIRNAME}/roles/${pbm}" ]] || {
        for d in tasks templates handlers files; do
            mkdir -p roles/${pbm}/$d
        done
        cat > ${DIRNAME}/roles/${pbm}/tasks/main.yml <<EOF
---
  - name: multiple commands
    shell: |
      whoami
      cat hosts
      id
    register: rst_msg
    notify: restart xxx

  - debug: var=rst_msg
...
EOF
        cat > ${DIRNAME}/roles/${pbm}/handlers/main.yml<<EOF
---
- name: restart xxx
#  service: name=tomcat state=restarted
  shell: |
    echo "XXX"
...
EOF
        cat > ${DIRNAME}/roles/${pbm}/templates/test.conf<<EOF
port={{ https_port }}
EOF
        touch ${DIRNAME}/roles/${pbm}/files/test.file
    }
    return 0
}
main "$@"
