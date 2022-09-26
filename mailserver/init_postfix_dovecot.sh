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
VERSION+=("4dadaff[2022-08-12T14:30:55+08:00]:init_postfix_dovecot.sh")
################################################################################
TIMESPAN=$(date '+%Y%m%d%H%M%S')
VMAIL_USER=${VMAIL_USER:-vmail}
VMAIL_GROUP=${VMAIL_GROUP:-vmail}
VMAIL_UGID=${VMAIL_UGID:-5000}
MAIL_LIST=${MAIL_LIST:-/etc/aliases}
LOGFILE=""

log() {
    echo "######$*" | tee ${LOGFILE} >&2
}

backup() {
    src=${1}
    log "BACKUP: ${src} ${TIMESPAN} "
    cat ${src} 2>/dev/null > ${src}.orig.${TIMESPAN} || true
}


postconf_e() {
    log "postconf -e \"${*}\""
    postconf -e "${*}"
}

init_vmail_user() {
    local maildir=${1}
    log "init ${VMAIL_USER}:${VMAIL_GROUP}(${VMAIL_UGID}:${VMAIL_UGID}) user, HOME=${maildir}"
    userdel -f -r ${VMAIL_USER} || true
    groupdel -f ${VMAIL_GROUP} || true
    getent group ${VMAIL_GROUP} >/dev/null || groupadd -g ${VMAIL_UGID} ${VMAIL_GROUP} 2>/dev/null || true
    getent passwd ${VMAIL_USER} >/dev/null || useradd --system -g ${VMAIL_GROUP} -u ${VMAIL_UGID} ${VMAIL_USER} -d ${maildir} --create-home -s /sbin/nologin -c "virtual mail user" 2>/dev/null || true
    chown -R ${VMAIL_USER}:${VMAIL_GROUP} ${maildir}
}

set_postfix_mail_list() {
    local domain=${1}
    log "init postfix alias, can as MailList"
    postconf_e "alias_database = hash:${MAIL_LIST}"
    postconf_e "alias_maps = hash:${MAIL_LIST}"
    log "alias ${MAIL_LIST}, list name must exist in passwd_db/ldap"
    cat <<EOF|tee ${LOGFILE}>"${MAIL_LIST}"
postmaster: root
mylist: user1@${domain}, test@sample.com
EOF
    postalias "${MAIL_LIST}"
    echo "init postfix virtual domain alias, Email Redirect OK"
    postconf_e "virtual_alias_domains = ${domain}"
    postconf_e "virtual_alias_maps = hash:/etc/postfix/virtual"
    log "virtual alias /etc/postfix/virtual"
    cat <<EOF |tee ${LOGFILE}>/etc/postfix/virtual
postmaster@${domain}  user2@${domain}
admin@${domain}       user1@${domain}
#@${domain}           catch-all@domain.com
EOF
    postmap /etc/postfix/virtual || true
}

set_postfix_ldap_local_recipient_map() {
    local ldap_host=${1}
    local ldap_port=${2}
    local ldap_tls=${3}
    local ldap_dn=${4}
    local ldap_pw=${5}
    local ldap_base=${6}
    log "Set Postfix local_recipient_map, so not local user can not post mails."
    log "Edit /etc/postfix/ldap-localusers.cf for ldap login info"
    postconf_e 'local_recipient_maps = ldap:/etc/postfix/ldap-localusers.cf unix:passwd.byname'
    cat <<EOF |tee ${LOGFILE} >/etc/postfix/ldap-localusers.cf
bind             = $( [ -z "${ldap_dn}" ] && echo -n no || echo -n yes )
${ldap_dn:+bind_dn          = ${ldap_dn}}
${ldap_pw:+bind_pw          = ${ldap_pw}}
start_tls        = ${ldap_tls}
tls_require_cert = no
# # #
server_host      = ${ldap_host}
server_port      = ${ldap_port}
search_base      = ${ldap_base}
# # #
query_filter     = (&(uid=%u))
# query_filter = (&(uid=%u)(accountStatus=active))
result_attribute = uid
version          = 3
EOF
    log "check postfix ldap local user, output: user1, -v verbose"
    postmap -q 'user1' ldap:/etc/postfix/ldap-localusers.cf || true
}

init_postfix() {
    local name=${1}
    local domain=${2}
    local maildir=${3}
    local cert=${4}
    local key=${5}
    log "REINIT POSTFIX"
    rm -f /etc/postfix/main.cf /etc/postfix/master.cf 2>/dev/null
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure postfix 2>/dev/null || true
    # postmap need main.cf config item. so execute here
    echo "$domain" > /etc/mailname

    postconf_e 'myorigin = /etc/mailname'
    postconf_e "smtpd_banner = ESMTP ${domain}"
    postconf_e "myhostname = ${name}.${domain}"
    postconf_e "mydomain = ${domain}"
    # postconf_e "setgid_group = postdrop"
    # postconf_e "sendmail_path = $(which sendmail)"
    # mailq_path = /usr/bin/mailq
    # message_size_limit = 10485760 # 限制单封邮件的最大长度
    # mailbox_size_limit = 20480000 # 单封邮件大小限制，单位字节
    # mail_owner = postfix          # postfix daemon 进程的运行身份
    postconf_e "mailbox_size_limit = 10485760"
    postconf_e 'inet_interfaces = all'
    postconf_e 'inet_protocols = ipv4'
    postconf_e 'mydestination = $mydomain, localhost.$mydomain, localhost'
    postconf_e 'alias_maps = '
    ####################
    postconf_e 'mailbox_transport = lmtp:unix:private/dovecot-lmtp'
    log "turn off local recipient checking in the Postfix SMTP server!!!!"
    postconf_e 'local_recipient_maps ='
    ####################
    postconf_e 'html_directory = no'
    #This is super important; we will only allow authenticated mail below.
    postconf_e 'smtpd_sasl_auth_enable = yes'
    postconf_e 'smtpd_sasl_type = dovecot'
    postconf_e 'smtpd_sasl_path = private/auth'
    postconf_e 'smtpd_sasl_security_options = noanonymous'
    postconf_e 'smtpd_sasl_tls_security_options = $smtpd_sasl_security_options'
    postconf_e 'smtpd_sasl_local_domain = $mydomain'
    postconf_e 'broken_sasl_auth_clients = yes'
    postconf_e 'smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination'
    #Authed clients can specify any destination domain.
    postconf_e 'smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination'
    postconf_e 'tls_medium_cipherlist = AES128+EECDH:AES128+EDH'
    postconf_e 'smtp_use_tls=yes'
    # the preceding line and this line make sure we're sending mail encrypted if possible
    postconf_e 'smtp_tls_security_level = may'
    # disable insecure protocols'
    postconf_e 'smtp_tls_mandatory_protocols = !SSLv2,!SSLv3,!TLSv1,!TLSv1.1'
    postconf_e 'smtp_tls_protocols=!SSLv2,!SSLv3,!TLSv1,!TLSv1.1'
    postconf_e 'smtp_tls_mandatory_ciphers = medium'
    postconf_e "smtp_tls_cert_file = ${cert}"
    postconf_e "smtp_tls_key_file = ${key}"
    postconf_e 'smtpd_use_tls=yes'
    # the preceding line and this line make sure mail coming in to us is encrypted if possible
    postconf_e 'smtpd_tls_security_level = may'
    postconf_e 'smtpd_tls_auth_only = yes'
    postconf_e 'smtpd_tls_mandatory_protocols = !SSLv2,!SSLv3,!TLSv1,!TLSv1.1'
    postconf_e 'smtpd_tls_protocols=!SSLv2,!SSLv3,!TLSv1,!TLSv1.1'
    postconf_e 'smtpd_tls_mandatory_ciphers = medium'
    postconf_e "smtpd_tls_cert_file = ${cert}"
    postconf_e "smtpd_tls_key_file = ${key}"
    postconf_e 'smtpd_tls_received_header = yes'
    postconf_e 'smtpd_tls_session_cache_timeout = 3600s'
    postconf_e 'tls_random_source = dev:/dev/urandom'
    # security fix: NVT: Check if Mailserver answer to VRFY and EXPN requests (OID: 1.3.6.1.4.1.25623.1.0.100072)
    postconf_e 'disable_vrfy_command = yes'

    log "Enable SMTPS and MSA"
    backup /etc/postfix/master.cf
    sed -i -E \
        -e 's/^\s*#*submission\s*inet\s*.*/submission inet n   -   y   -   -   smtpd/g' \
        -e 's/^\s*#*smtps\s*inet\s*.*/smtps inet n   -   y   -   -   smtpd/g' \
        -e 's/^\s*#*\s*-o smtpd_tls_wrappermode=yes/  -o smtpd_tls_wrappermode=yes/g' \
        /etc/postfix/master.cf
}

set_dovecot_mailbox_ldap_auth() {
    local ldap_host=${1}
    local ldap_port=${2}
    local ldap_tls=${3}
    local ldap_dn=${4}
    local ldap_pw=${5}
    local ldap_base=${6}
    log "DOVECOT LDAP AUTH"
    # auth_username_format = %Ln L:lowercase, n:drop @domain
    backup /etc/dovecot/conf.d/10-auth.conf
    sed --quiet -i -E \
        -e '/(auth_username_format\s*=|disable_plaintext_authi\s*=|auth_mechanisms\s*=|include\s+auth-system.conf.ext|include\s+auth-ldap.conf.ext).*/!p' \
        -e '$a#!include auth-system.conf.ext' \
        -e '$a!include auth-ldap.conf.ext' \
        -e '$adisable_plaintext_auth = no' \
        -e '$aauth_mechanisms = plain login' \
        -e '$aauth_username_format = %Ln' \
        /etc/dovecot/conf.d/10-auth.conf
    backup /etc/dovecot/conf.d/auth-ldap.conf.ext
    cat <<EOF |tee ${LOGFILE}| tee /etc/dovecot/conf.d/auth-ldap.conf.ext
passdb {
  driver = ldap
  args = /etc/dovecot/dovecot-ldap.conf.ext
}
userdb {
  driver = ldap
  args = /etc/dovecot/dovecot-ldap.conf.ext
}
EOF
    backup /etc/dovecot/dovecot-ldap.conf.ext
    cat <<EOF |tee ${LOGFILE}| tee /etc/dovecot/dovecot-ldap.conf.ext
${ldap_dn:+dn                  = ${ldap_dn}}
${ldap_pw:+dnpass              = ${ldap_pw}}
# if tls yes, ldap_host must same as "ldap tls pem common name".
# add ldap_host in /etc/hosts.
tls                 = ${ldap_tls}
tls_require_cert    = never

hosts               = ${ldap_host}:${ldap_port}
# base = ou=People,dc=test,dc=mail
base                = ${ldap_base}
user_attrs          = mailUidNumber=${VMAIL_UGID},mailGidNumber=${VMAIL_UGID}
default_pass_scheme = SSHA
ldap_version        = 3
auth_bind           = yes
blocking            = yes
EOF
}

set_mailbox_password_auth() {
    local maildir=${1}
    local domain=${2}
    log "dovecot passwd_file auth"
    # passwd file auth
    # ssl = required, client wants to use AUTH PLAIN is ok
    # auth_username_format = %Lu L:lowercase, u:whole user, include @domain
    backup /etc/dovecot/conf.d/10-auth.conf
    sed --quiet -i -E \
        -e '/(auth_username_format\s*=|disable_plaintext_authi\s*=|auth_mechanisms\s*=|include\s+auth-system.conf.ext|include\s+auth-passwdfile.conf.ext).*/!p' \
        -e '$a#!include auth-system.conf.ext' \
        -e '$a!include auth-passwdfile.conf.ext' \
        -e '$adisable_plaintext_auth = no' \
        -e '$aauth_mechanisms = plain login' \
        -e '$aauth_username_format = %Lu' \
        /etc/dovecot/conf.d/10-auth.conf
    backup /etc/dovecot/conf.d/auth-passwdfile.conf.ext
    cat <<EOF |tee ${LOGFILE}| tee /etc/dovecot/conf.d/auth-passwdfile.conf.ext
passdb {
  driver = passwd-file
  args = scheme=SHA512-CRYPT /etc/dovecot/passwd
}
userdb {
  driver = static
  args = uid=${VMAIL_UGID} gid=${VMAIL_UGID} home=${maildir}/%d/%n allow_all_users=yes
}
EOF
    # Add users
    backup /etc/dovecot/passwd
    cat <<EOF |tee ${LOGFILE}| tee /etc/dovecot/passwd
# doveadm pw -s SHA512-CRYPT -p password | cut -d '}' -f2
admin@${domain}:$(doveadm pw -s SHA512-CRYPT -p password | cut -d '}' -f2)
user1@${domain}:$(doveadm pw -s SHA512-CRYPT -p password | cut -d '}' -f2)
user2@${domain}:$(doveadm pw -s SHA512-CRYPT -p password | cut -d '}' -f2)
EOF
    chmod 600 /etc/dovecot/passwd
}

set_mailbox_autocreate() {
    log "DOVECOT MAILBOX AUTOCREATE"
    backup /etc/dovecot/conf.d/15-mailboxes.conf
    sed --quiet -i -E \
        -e '/^namespace\s+inbox\s*\{/,/^\}/!p' \
        /etc/dovecot/conf.d/15-mailboxes.conf
    cat <<EOF |tee ${LOGFILE} | tee -a /etc/dovecot/conf.d/15-mailboxes.conf
namespace inbox {
  mailbox Drafts {
    auto = subscribe
    special_use = \Drafts
  }
  mailbox Junk {
    auto = subscribe
    special_use = \Junk
  }
  mailbox Sent {
    auto = subscribe
    special_use = \Sent
  }
  mailbox Trash {
    special_use = \Trash
  }
}
EOF
}

init_dovecot() {
    local maildir=${1}
    local cert=${2}
    local key=${3}
    local domain=${4}
    log "REINIT DOVECOT"
    rm -f /etc/dovecot/conf.d/* /etc/dovecot/* 2>/dev/null || true
    UCF_FORCE_CONFFMISS=1 DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dovecot-core 2>/dev/null | true
    log "Enable DOVECOT SSL"
    backup /etc/dovecot/conf.d/10-ssl.conf
    sed --quiet -i -E \
        -e '/^\s*(ssl\s*=|ssl_cert\s*=|ssl_key\s*=).*/!p' \
        -e '$assl = required' \
        -e "\$assl_cert = <${cert}" \
        -e "\$assl_key = <${key}" \
        /etc/dovecot/conf.d/10-ssl.conf
        # ssl_dh = </usr/share/dovecot/dh.pem
    backup /etc/dovecot/conf.d/10-mail.conf
    sed --quiet -i -E \
        -e '/^\s*(mail_location\s*=|mail_home\s*=|mail_access_groups\s*=|default_login_user\s*=).*/!p' \
        -e "\$amail_location = maildir:${maildir}/%d/%n" \
        -e "\$amail_home = ${maildir}/%n" \
        -e "\$amail_access_groups = ${VMAIL_GROUP}" \
        -e "\$adefault_login_user = ${VMAIL_USER}" \
        -e "\$amail_uid = ${VMAIL_UGID}" \
        -e "\$amail_gid = ${VMAIL_UGID}" \
        /etc/dovecot/conf.d/10-mail.conf

    backup /etc/dovecot/conf.d/10-master.conf
    sed --quiet -i -E \
        -e '/^service\s+(auth|imap-login|pop3-login|lmtp)\s*\{/,/^\}/!p' \
        /etc/dovecot/conf.d/10-master.conf
    cat <<EOF |tee ${LOGFILE} | tee -a /etc/dovecot/conf.d/10-master.conf
service auth {
  unix_listener auth-userdb {
    mode = 0600
    user = ${VMAIL_USER}
    group = ${VMAIL_GROUP}
  }
  unix_listener auth-client {
    path = /var/spool/postfix/private/auth
    mode = 0666
    user = postfix
    group = postfix
  }
  user = root
}
service imap-login {
  inet_listener imap {
    #port = 143
  }
  inet_listener imaps {
    port = 993
    ssl = yes
  }
  process_min_avail = 1
  user = ${VMAIL_USER}
}
service pop3-login {
  inet_listener pop3 {
    #port = 110
  }
  inet_listener pop3s {
    port = 995
    ssl = yes
  }
  user = ${VMAIL_USER}
}
# Set up LMTP - we use this for allowing Dovecot to get mail handed off from Postfix
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0666
    user = postfix
    group = postfix
  }
}
EOF
}

set_debug() {
    local domain=${1}

    postconf_e 'debug_peer_level = 2'
    postconf_e "debug_peer_list = ${domain}"
    backup /etc/dovecot/conf.d/10-logging.conf
    sed --quiet -i -E \
        -e '/^\s*(auth_verbose\s*=|mail_debug\s*=).*/!p' \
        -e '$aauth_verbose = yes' \
        -e '$amail_debug = yes' \
        /etc/dovecot/conf.d/10-logging.conf
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
         env: VMAIL_USER=vmail
              VMAIL_GROUP=vmail
              VMAIL_UGID=5000
              MAIL_LIST=/etc/aliases
        --name     *    <str>  name
        --domain   *    <str>  domain name "sample.org"
        --dir      *    <str>  mail directory location
        --cert     *    <str>  ssl cert file
        --key      *    <str>  ssl key file
        --ldap_dn       <str>  ldap login dn
        --ldap_pw       <str>  ldap login password
        --ldap_tls             use ldap starttls, default no use start tls
        --ldap_host   * <str>  ldap host, if null use password file auth
        --ldap_port     <int>  ldap port, default 389
        --ldap_base   * <str>  ldap search base
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        # test on debian bullseys!!
        apt -y install gnupg apt-transport-https && wget -q -O- 'https://repo.dovecot.org/DOVECOT-REPO-GPG' |
            gpg --dearmor > /etc/apt/trusted.gpg.d/dovecot-archive-keyring.gpg
        echo "deb https://repo.dovecot.org/ce-2.3-latest/debian/bullseye bullseye main" >/etc/apt/sources.list.d/dovecot.list
        apt update && apt -y install postfix postfix-ldap dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-ldap
        # check ssl: openssl s_client -servername mail.sample.org -connect mail.sample.org:pop3s
        # check starttls: openssl s_client -host mail.sample.org -port 25/465/587/110/143 -starttls smtp/smtp/smtp/pop3/imap
        postconf -a (SASL support in the SMTP server)
        postconf -A (SASL support in the SMTP+LMTP client)
        doveconf -a/postconf
FUSE / GlusterFS
    FUSE caches dentries and file attributes internally. If you're using multiple
GlusterFS clients to access the same mailboxes, you're going to have problems. Worst
of these problems can be avoided by using NFS cache flushes, which just happen to
work with FUSE as well:
    mail_nfs_index = yes
    mail_nfs_storage = yes
These probably don't work perfectly.
EOF
    exit 1
}

# testsaslauthd -u user1 -p password -f /var/spool/postfix/var/run/saslauthd/mux
# saslfinger -s
main() {
    local name="" domain="" maildir="" cert="" key=""
    local ldap_dn="" ldap_pw="" ldap_tls="no" ldap_host="" ldap_port=389 ldap_base=""
    local opt_short=""
    local opt_long="name:,domain:,dir:,cert:,key:,ldap_dn:,ldap_pw:,ldap_tls,ldap_host:,ldap_port:,ldap_base:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            --name)         shift; name=${1}; shift;;
            --domain)       shift; domain=${1}; shift;;
            --dir)          shift; maildir=${1}; shift;;
            --cert)         shift; cert=${1}; shift;;
            --key)          shift; key=${1}; shift;;
            --ldap_dn)      shift; ldap_dn=${1}; shift;;
            --ldap_pw)      shift; ldap_pw=${1}; shift;;
            --ldap_tls)     shift; ldap_tls="yes";;
            --ldap_host)    shift; ldap_host=${1}; shift;;
            --ldap_port)    shift; ldap_port=${1}; shift;;
            --ldap_base)    shift; ldap_base=${1}; shift;;
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
    [ -z "${name}" ] && usage "command line error!"
    [ -z "${domain}" ] && usage "command line error!"
    [ -z "${maildir}" ] && usage "command line error!"
    [ -z "${cert}" ] && usage "command line error!"
    [ -z "${key}" ] && usage "command line error!"
    # Preferred permissions: root:root 0444
    chmod 0444 "${cert}" || true
    # Preferred permissions: root:root 0400
    chmod 0400 "${key}" || true
    init_vmail_user "${maildir}"
    init_postfix "${name}" "${domain}" "${maildir}" "${cert}" "${key}"
    set_postfix_mail_list "${domain}"
    init_dovecot "${maildir}" "${cert}" "${key}" "${domain}"
    set_mailbox_autocreate
    [ -z "${ldap_host}" ] && set_mailbox_password_auth "${maildir}" "${domain}"
    [ -z "${ldap_host}" ] || {
        local d1="" d2="" d3=""
        [ -z "${ldap_base}" ] && usage "ldap must set ldap_host & ldap_base"
        set_postfix_ldap_local_recipient_map "${ldap_host}" "${ldap_port}" "${ldap_tls}" "${ldap_dn}" "${ldap_pw}" "${ldap_base}"
        set_dovecot_mailbox_ldap_auth "${ldap_host}" "${ldap_port}" "${ldap_tls}" "${ldap_dn}" "${ldap_pw}" "${ldap_base}"
        log "modify: /etc/dovecot/dovecot-ldap.conf.ext"
        log "hosts, base, tls, hosts -> USE DNS NAME(same as ldap PKI Sign cert DN)"
    }
    # set_debug "${domain}"
    log "CHECK ENV"
    systemctl restart dovecot postfix || true
    doveadm user user1 | tee ${LOGFILE} || true
    doveadm auth login user1 password | tee ${LOGFILE} || true
    log "ALL OK ${TIMESPAN}"
    return 0
}
main "$@"
