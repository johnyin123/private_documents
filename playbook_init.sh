#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("bc71876[2022-12-08T14:15:12+08:00]:playbook_init.sh")
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
    try mkdir -p "${dir}/defaults/"

    write_file "${dir}/defaults/main.yml" <<EOF
---
# site.yum -i hosts -e "testvalue=9999"
# if no other value is supplied in inventory or as a parameter, this value will be used
testvalue: 80
EOF

    write_file "${dir}/tasks/main.yml" <<EOF
---
- include: ${pbm}.yml
  tags:
    - ${pbm}
EOF
    write_file "${dir}/tasks/${pbm}.yml" <<EOF
---
- name: multiple commands
  shell: |
    whoami
    cat /etc/hosts
    id
  register: output
  notify: restart xxx
# copy register value to local file
- local_action: copy content="{{ item.value }}" dest="/tmp/{{ item.name }}-{{ ansible_date_time.date }}-{{ ansible_hostname }}.log"
  with_items:
    - name: cmdoutput
      value: "{{ output }}"

# output register value
- debug: msg="{{ output }}"
- debug: msg="{{ testvalue }}"

# Task called by include
- include: func.yml parm={{ item }}
  with_items:
    - parm1
    - parm2

# - name: execute python script
#   script: mypython.py
# # and mypython.py file should be in files in the same role
EOF
    write_file "${dir}/tasks/func.yml" <<EOF
---
- name: called by include task
  shell:
    echo "{{ parm }}"
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

demo_adduser() {
    echo "include call adduser.yml"
    cat << 'EOF'
# python -c 'import crypt; print crypt.crypt("password", "$1$SomeSalt$")'
- include: adduser.yml username={{ item }} password=$1$SomeSalt$/jbIwfYCu0MxPBND2EtRH.
  with_items:
    - newuser1
    - newuser2
EOF
    echo "start ========= adduser.yml ============="
    cat << 'EOF'
---
# - name: addgroup {{ username }}
#   group: name={{ username }} system=no
- name: adduser {{ username }} with password
  user: name={{ username }} password={{ password }} group={{ username }} home=/home/{{ username }} shell=/bin/bash system=no
EOF
    echo "end ========= adduser.yml ============="
}
demo_insert_notexist() {
    echo "start ========= insert if not exist ============="
    cat <<'EOF'
- name: Test for line
  shell: grep -c "^keyword" /file || true
  register: test_grep

- name: add if not exist
  lineinfile:
    dest: /file
    line: keyword=127.0.0.1
  when: test_grep.stdout == "0"
EOF
    echo "end ========= insert if not exist ============="
}

demo() {
    demo_adduser
    demo_insert_notexist
    echo "end demos ****************************************"
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -D     dest directory
        -m     task name
        -H     task host group name
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
            # ./site.yml -i hosts
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
            -h | --help)    shift; demo; usage;;
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
