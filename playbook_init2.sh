#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("9cd85d5[2022-12-07T14:51:41+08:00]:playbook_init2.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
init_playbook_module() {
    local pbm=${1}
    local dir=${2}
    info_msg "Init ${pbm} playbook direcotry: ${dir}\n"
    directory_exists "${dir}" && {
        error_info "${pbm} direcotyr ${dir} exists!!\n"
        return 1
    }
    try mkdir -p "${dir}"
    try mkdir -p "${dir}/tasks/"
    try mkdir -p "${dir}/templates/"
    try mkdir -p "${dir}/handlers/"
    try mkdir -p "${dir}/files/"

    write_file "${dir}/tasks/main.yml" <<EOF
---
- include: ${pbm}.yml
  tags:
    - ${pbm}
EOF
    write_file "${dir}/tasks/${pbm}.yml" <<EOF
---
# ansible-playbook ${pbm}.yml -i hosts -e 'env=local'
- name: multiple commands
  shell: |
    whoami
    cat /etc/hosts
    id
  register: output
  notify: restart xxx
- copy: content="{{ output }}" dest=/home/johnyin/ansible/test/output.log

- debug:
    msg: "{{ output }}"
EOF
    write_file "${dir}/handlers/main.yml" <<EOF
---
- name: restart xxx
#  service: name=tomcat state=restarted
  shell: |
    echo "XXX"
EOF
    write_file "${dir}/templates/test.conf" <<EOF
port={{ https_port }}
EOF
    touch "${dir}/files/test.file"
    return 0
}

init_playbook() {
    local pbm=${1:-demo}
    local host=${2:-web}
    local dir=${3}
    info_msg "Init direcotrys\n"
    try mkdir -p "${dir}/group_vars"
    try mkdir -p "${dir}/host_vars"

    file_exists "${dir}/site.yml" && {
        write_file "${dir}/site.yml" 1 <<EOF

- hosts: ${host}
  roles:
    - ${pbm}
EOF
    } || {
        write_file "${dir}/site.yml" <<EOF
#!/usr/bin/env ansible-playbook
---
- hosts: ${host}
  roles:
    - ${pbm}
EOF
    chmod 755 "${dir}/site.yml"
    }

    file_exists "${dir}/hosts" || {
        write_file "${dir}/hosts" <<EOF
# ansible_connection=ssh
# ansible_ssh_pass=password

[${host}]
srv1 ansible_host=192.168.168.2 ansible_port=22 ansible_user=root
srv2 ansible_host=192.168.168.3 ansible_port=22 ansible_user=root
EOF
    }

    file_exists "${dir}/group_vars/${pbm}.yml" || {
        write_file "${dir}/group_vars/${pbm}.yml" <<EOF
#http_port: 8080
#https_port: 8443
EOF
    }

    file_exists "${dir}/host_vars/srv1.yml" || {
        write_file "${dir}/host_vars/srv1.yml" <<EOF
#http_port: 8080
#https_port: 8443
EOF
    }
    init_playbook_module "${pbm}" "${dir}/roles/${pbm}" || return $?
    return 0
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -D     dest directory
        -m     playbook name
        -H     playbook host
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
            # mkdir ~/.pip/
            # cat <<EOF >~/.pip/pip.conf
            # [global]
            # index-url = https://pypi.tuna.tsinghua.edu.cn/simple
            # EOF
            # python3 -m venv kq_venv --python python3 / virtualenv kq_venv --python python3.9
            # source kq_venv/bin/activate
            # pip install ansible==2.10.7
            # keep remote file in remote ~/.ansible/tmp/: ANSIBLE_KEEP_REMOTE_FILES=1 ansible-playbook site.yml -i hosts
EOF
    exit 1
}
main() {
    local pbm= host= dir=
    local opt_short="m:H:D:"
    local opt_long=""
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -m)     shift; pbm=${1}; shift;;
            -H)     shift; host=${1}; shift;;
            -D)     shift; dir=${1}; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [ -z "${pbm}" ] || [ -z "${host}" ] || [ -z "${dir}" ] && {
        usage "Need module & hosts & direcotry"
    }
    init_playbook "${pbm}" "${host}" "${dir}"
    return 0
}
main "$@"
