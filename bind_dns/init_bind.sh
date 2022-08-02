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
VERSION+=("3471db2[2022-08-02T15:11:50+08:00]:init_bind.sh")
################################################################################
TIMESPAN=$(date '+%Y%m%d%H%M%S')
init_bind() {
    local domain=${1}
    local lan_addr=${2}
    local wan_addr=${3}
    local fake=${4:-}
    local l1= l2= l3= l4=
    IFS='.' read -r l1 l2 l3 l4 <<< "${lan_addr}"
    local w1= w2= w3= w4=
    IFS='.' read -r w1 w2 w3 w4 <<< "${wan_addr}"
    mkdir -p "/etc/bind/${domain}" && chown -R root:bind "/etc/bind/${domain}"
    # remove named.conf.default-zones, when useing view!
    sed --quiet -i.orig.${TIMESPAN} -E \
        -e "/(named.conf.${domain}|named.conf.default-zones|logging.conf).*/!p" \
        -e "\$ainclude \"/etc/bind/${domain}/${domain}.conf\";" \
        /etc/bind/named.conf

    cat /etc/bind/named.conf.options > /etc/bind/named.conf.options.orig.${TIMESPAN}
    cat <<EOF > /etc/bind/named.conf.options
options {
    listen-on port 53 { any; };
    listen-on-v6 { none; };
    directory "/var/cache/bind";
    allow-query { any; };
    allow-query-cache {any;};
    recursion yes;
    forwarders {
        114.114.114.114;
    };
    dnssec-enable yes;
    dnssec-validation yes;
    dnssec-lookaside auto;
};
EOF

    cat <<EOF > /etc/bind/${domain}/${domain}.conf
acl net_wan {
    { !${l1}.${l2}.${l3}.0/24; any; };
};
acl net_lan {
    ${l1}.${l2}.${l3}.0/24;
};
view "view_wan" {
    match-clients {net_wan;};
    zone "${domain}" IN {
        type master;
        file "/etc/bind/${domain}/${domain}.wan";
        allow-update { none; };
    };
    zone "${w3}.${w2}.${w1}.in-addr.arpa" IN {
        type master;
        file "/etc/bind/${domain}/${w1}.${w2}.${w3}.wan";
        allow-update { none; };
    };
};
view "view_lan" {
    match-clients {net_lan;};${fake}
    zone "${domain}" IN {
        type master;
        file "/etc/bind/${domain}/${domain}.lan";
        allow-update { none; };
    };
    zone "${l3}.${l2}.${l1}.in-addr.arpa" IN {
        type master;
        file "/etc/bind/${domain}/${l1}.${l2}.${l3}.lan";
        allow-update { none; };
    };
};
EOF
    cat <<EOF > /etc/bind/${domain}/${domain}.lan
\$TTL 86400
@   IN  SOA     ns.${domain}. root.${domain}. (
    2021081801  ;Serial
    3600        ;Refresh
    1800        ;Retry
    604800      ;Expire
    86400       ;Minimum TTL
)
        NS          ns.${domain}.
        MX 3        mail.${domain}.
@       A           ${lan_addr}
ns      A           ${lan_addr}
mail    A           ${lan_addr}
demo    A           ${lan_addr}
ftp     CNAME       demo.${domain}.
; wildcard-dns
*       CNAME       @
EOF
    cat <<EOF > /etc/bind/${domain}/${l1}.${l2}.${l3}.lan
\$TTL 86400
@   IN  SOA     ns.${domain}. root.${domain}. (
    2021081801  ;Serial
    3600        ;Refresh
    1800        ;Retry
    604800      ;Expire
    86400       ;Minimum TTL
)
        IN  NS      ns.${domain}.
${l4}     IN  PTR     ns.${domain}.
${l4}     IN  PTR     mail.${domain}.
EOF
    cat <<EOF > /etc/bind/${domain}/${domain}.wan
\$TTL 86400
@   IN  SOA     ns.${domain}. root.${domain}. (
    2021081801  ;Serial
    3600        ;Refresh
    1800        ;Retry
    604800      ;Expire
    86400       ;Minimum TTL
)
        NS          ns.${domain}.
        MX 3        mail.${domain}.
@       A           ${wan_addr}
ns      A           ${wan_addr}
mail    A           ${wan_addr}
demo    A           ${wan_addr}
ftp     CNAME       demo.${domain}.
; wildcard-dns
*       CNAME       @
EOF
    cat <<EOF > /etc/bind/${domain}/${w1}.${w2}.${w3}.wan
\$TTL 86400
@   IN  SOA     ns.${domain}. root.${domain}. (
    2021081801  ;Serial
    3600        ;Refresh
    1800        ;Retry
    604800      ;Expire
    86400       ;Minimum TTL
)
        IN  NS      ns.${domain}.
${w4}       IN  PTR     ns.${domain}.
${w4}       IN  PTR     mail.${domain}.
EOF
}

init_bind_log() {
    # apparmor="DENIED", see: /etc/apparmor.d/usr.sbin.named
    mkdir -p /var/log/named || true
    chown bind:bind /var/log/named || true
    cat <<EOF > /etc/bind/logging.conf
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
    echo 'include "/etc/bind/logging.conf";' >> /etc/bind/named.conf
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        --domain   *    <str>  domain name "sample.org"
        --lan      *    <str>  lan ipaddr, 192.168.1.2
        --wan      *    <str>  wan ipaddr.
        --log                  with named access log (/var/log/named/named.log), default no log 
        -f|--fake                support fake any domain
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        # apt -y install bind9 bind9utils
        # named-checkconf, check named config
        # rndc reload, reload named config when add A/CNAME record
        # dig -x <ipaddr>, dig <domain>, dig sample.org MX
    Set BIND to use only IPv4: sed -i -e 's/OPTIONS=.*/OPTIONS="-u bind -4"/g' /etc/default/named
EOF
    exit 1
}
main() {
    local domain="" lan="" wan="" access_log="" fake=""
    local opt_short="f"
    local opt_long="domain:,lan:,wan:,log,fake,"
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
            -f|--fake)      shift; fake="
    zone \".\" {
        type master;
        file \"/etc/bind/fakeroot.lan\";
    };";;
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
    [ -z "${domain}" ] && usage "command line error!"
    [ -z "${lan}" ] && usage "command line error!"
    [ -z "${wan}" ] && usage "command line error!"
    init_bind "${domain}" "${lan}" "${wan}" "${fake}"
    [ -z "${fake}" ] || {
        cat <<EOF >/etc/bind/fakeroot.lan
\$TTL 86400
@ IN SOA ns.domain.com. hostmaster.domain.com. ( 1 3h 1h 1w 1d )
                NS ${lan}
*               A  ${lan}
www.test.com    A  192.168.1.20
EOF
    }
    [ -z "${access_log}" ] || init_bind_log
    echo "ALL OK ${TIMESPAN}"
    return 0
}
main "$@"
