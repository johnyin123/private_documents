#!/usr/bin/env bash
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("f0e9486[2022-08-24T13:52:11+08:00]:init_bind.sh")
################################################################################
TIMESPAN=$(date '+%Y%m%d%H%M%S')
SERIAL=$(date '+%Y%m%d%H')

log() {
    echo "######$*" | tee ${LOGFILE} >&2
}

backup() {
    src=${1}
    log "BACKUP: ${src} ${TIMESPAN} "
    cat ${src} 2>/dev/null > ${src}.orig.${TIMESPAN} || true
}

gen_domain_zone() {
    local domain=${1}
    local ipaddr=${2}
    log "GEN ${domain} domain zone"
    cat <<EOF |tee ${LOGFILE}
\$TTL 86400
@   IN  SOA     ns.${domain}. root.${domain}. (
    ${SERIAL}  ;Serial
    3600        ;Refresh
    1800        ;Retry
    604800      ;Expire
    86400       ;Minimum TTL
)
        NS          ns.${domain}.
        MX 3        mail.${domain}.
@       A           ${ipaddr}
ns      A           ${ipaddr}
mail    A           ${ipaddr}
        TXT         "v=spf1 ip4:${ipaddr} include:spf.${domain} -all"
demo    A           ${ipaddr}
ftp     CNAME       demo.${domain}.
; wildcard-dns
*       CNAME       @
EOF
# TXT         "v=spf1 ip4:${ipaddr} ip4:<ip> include:spf.${domain} -all"
}

gen_reverse_mapped_zone_file() {
    local domain=${1}
    local ipaddr=${2}
    local arpa_file=${3}
    local w1= w2= w3= w4=
    IFS='.' read -r w1 w2 w3 w4 <<< "${ipaddr}"
    log "GEN ${domain} reverse_mapped zone"
    [ -e "${arpa_file}" ] || {
    # arpa rev file not exist, so create it
    cat <<EOF |tee ${LOGFILE}| tee ${arpa_file}
\$TTL 86400
@   IN  SOA     ns.${domain}. root.${domain}. (
    ${SERIAL}  ;Serial
    3600        ;Refresh
    1800        ;Retry
    604800      ;Expire
    86400       ;Minimum TTL
)
         IN  NS      ns.${domain}.
EOF
    }
    cat <<EOF |tee ${LOGFILE}| tee -a ${arpa_file}
; ${domain} Reverse-Mapped Zone Begin ${TIMESPAN}
${w4}     IN  PTR     ns.${domain}.
${w4}     IN  PTR     mail.${domain}.
; ${domain} Reverse-Mapped Zone End ${TIMESPAN}
EOF
}

aclview_addzone() {
    local acl_file=${1}
    local zone_file=${2}
    log "ADD ${zone_file} in ${acl_file}"
    backup ${acl_file}
    sed -E -i \
        -e "s|^\s*include\s+.*${zone_file}.*||g" \
        -e "/^\s*view\s+.*/ a\    include \"${zone_file}\";" \
        ${acl_file}
}

gen_zone() {
    local zone_name=${1}
    local domain_file=${2}
    log "GEN zone ${zone_name} domain ${domain_file}"
    cat <<EOF |tee ${LOGFILE}
zone "${zone_name}" IN {
    type master;
    file "${domain_file}";
    allow-update { none; };
};
EOF
}

gen_aclview() {
    local ipaddr=${1}
    local acl_name=${2}
    local w1= w2= w3= w4=
    IFS='.' read -r w1 w2 w3 w4 <<< "${ipaddr}"
    log "GEN acl ${acl_name} ${ipaddr}"
    cat <<EOF |tee ${LOGFILE}
acl ${acl_name} {
    // { !${w1}.${w2}.${w3}.0/24; any; };
    ${w1}.${w2}.${w3}.0/24;
};
view "view_${acl_name}" {
    match-clients {${acl_name};};
};
EOF
}

init_bind() {
    local domain=${1}
    local lan_addr=${2}
    local wan_addr=${3}
    local l1= l2= l3= l4= w1= w2= w3= w4=
    IFS='.' read -r l1 l2 l3 l4 <<< "${lan_addr}"
    IFS='.' read -r w1 w2 w3 w4 <<< "${wan_addr}"
    local acl_lan_file=/etc/bind/named.conf.acl.lan
    local acl_wan_file=/etc/bind/named.conf.acl.wan
    local arpa_lan_file=/etc/bind/${l1}.${l2}.${l3}.lan
    local arpa_wan_file=/etc/bind/${w1}.${w2}.${w3}.wan
    local domain_lan_file=/etc/bind/${domain}.lan
    local domain_wan_file=/etc/bind/${domain}.wan
    local zone_lan_file=/etc/bind/${domain}.zone.lan
    local zone_wan_file=/etc/bind/${domain}.zone.wan
    local arpa_zone_lan_file=/etc/bind/${l1}.${l2}.${l3}.zone.lan
    local arpa_zone_wan_file=/etc/bind/${w1}.${w2}.${w3}.zone.wan
    log "remove named.conf.default-zones, when useing view!"
    backup /etc/bind/named.conf
    sed --quiet -i -E \
        -e "/(named.conf.default-zones|named.conf.acl).*/!p" \
        -e "\$ainclude \"${acl_lan_file}\";" \
        -e "\$ainclude \"${acl_wan_file}\";" \
        /etc/bind/named.conf
    backup /etc/bind/named.conf.options
    cat <<EOF |tee ${LOGFILE}| tee /etc/bind/named.conf.options
options {
    listen-on port 53 { any; };
    listen-on-v6 { none; };
    directory "/var/cache/bind";
    // dump-file          "/var/named/data/cache_dump.db";
    // statistics-file    "/var/named/data/named_stats.txt";
    // memstatistics-file "/var/named/data/named_mem_stats.txt";
    version "not currently available";
    allow-query { any; };
    allow-query-cache {any;};
    recursion yes;
    forwarders {
        114.114.114.114;
    };
    // dnssec-enable yes;
    dnssec-validation yes;
    // dnssec-lookaside auto;
};
EOF
    [ -e "${acl_lan_file}" ] || gen_aclview "${lan_addr}" "net_lan" >> ${acl_lan_file}
    [ -e "${acl_wan_file}" ] || gen_aclview "${wan_addr}" "net_wan" >> ${acl_wan_file}

    gen_zone "${domain}" "${domain_lan_file}" > ${zone_lan_file}
    gen_zone "${domain}" "${domain_wan_file}" > ${zone_wan_file}
    aclview_addzone "${acl_lan_file}" "${zone_lan_file}"
    aclview_addzone "${acl_wan_file}" "${zone_wan_file}"

    gen_zone "${l3}.${l2}.${l1}.in-addr.arpa" "${arpa_lan_file}" > ${arpa_zone_lan_file}
    gen_zone "${w3}.${w2}.${w1}.in-addr.arpa" "${arpa_wan_file}" > ${arpa_zone_wan_file}
    aclview_addzone "${acl_lan_file}" "${arpa_zone_lan_file}"
    aclview_addzone "${acl_wan_file}" "${arpa_zone_wan_file}"

    gen_domain_zone "${domain}" "${lan_addr}" > ${domain_lan_file}
    gen_domain_zone "${domain}" "${wan_addr}" > ${domain_wan_file}

    gen_reverse_mapped_zone_file "${domain}" "${lan_addr}" "${arpa_lan_file}"
    gen_reverse_mapped_zone_file "${domain}" "${wan_addr}" "${arpa_wan_file}"
}

init_bind_log() {
    # apparmor="DENIED", see: /etc/apparmor.d/usr.sbin.named
    mkdir -p /var/log/named || true
    chown bind:bind /var/log/named || true
    log "GEN named log /etc/bind/logging.conf"
    cat <<EOF |tee ${LOGFILE}| tee /etc/bind/logging.conf
logging {
    channel mylog {
        file "/var/log/named/named.log" versions 3 size 20m;
        severity dynamic;
        print-time yes;
        print-category yes;
        print-severity yes;
    };
    category client         { mylog; };
    category config         { mylog; };
    category dnssec         { mylog; };
    category lame-servers   { mylog; };
    category network        { mylog; };
    category queries        { mylog; };
    category resolver       { mylog; };
    category security       { mylog; };
};
EOF
    grep -q '/etc/bind/logging.conf' /etc/bind/named.conf 2>/dev/nul || {
        echo 'include "/etc/bind/logging.conf";' >> /etc/bind/named.conf
    }
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        --domain   *    <str>  domain name "sample.org"
        --lan      *    <str>  lan ipaddr, 192.168.1.2
        --wan      *    <str>  wan ipaddr.
        --log                  with named access log (/var/log/named/named.log), default no log 
        -q|--quiet
        -l|--log <str>  log file
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        # apt -y install bind9 bind9utils
        # named-checkconf, check named config
        # rndc reload, reload named config when add A/CNAME record
        # dig -x <ipaddr>, dig <domain>, dig sample.org MX, dig txt mail.sample.org, dig txt mail.sample.org +short
    Set BIND to use only IPv4: sed -i -e 's/OPTIONS=.*/OPTIONS="-u bind -4"/g' /etc/default/named
EOF
    exit 1
}
main() {
    local domain="" lan="" wan="" access_log=""
    local opt_short="f"
    local opt_long="domain:,lan:,wan:,log,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            --domain)       shift; domain=${1}; shift;;
            --lan)          shift; lan=${1}; shift;;
            --wan)          shift; wan=${1}; shift;;
            --log)          shift; access_log=1;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; LOGFILE="-a ${1}"; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [ -z "${domain}" ] && usage "command line error!"
    [ -z "${lan}" ] && usage "command line error!"
    [ -z "${wan}" ] && usage "command line error!"
    init_bind "${domain}" "${lan}" "${wan}"
    [ -z "${access_log}" ] || init_bind_log
    log "ALL OK ${TIMESPAN}"
    named-checkconf
    systemctl restart named
    return 0
}
main "$@"
