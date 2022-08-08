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
VERSION+=("dcda8cc[2022-08-08T17:16:32+08:00]:init_postfix_dovecot.sh")
################################################################################
TIMESPAN=$(date '+%Y%m%d%H%M%S')
VMAIL_USER=${VMAIL_USER:-vmail}
VMAIL_GROUP=${VMAIL_GROUP:-vmail}
VMAIL_UGID=${VMAIL_UGID:-5000}
MAIL_LIST=${MAIL_LIST:-/etc/aliases}
LOGFILE=""

init_vmail_user() {
    local maildir=${1}
    echo "****init vmail user, HOME=${maildir}" | tee ${LOGFILE}
    userdel -f -r ${VMAIL_USER} || true
    groupdel -f ${VMAIL_GROUP} || true
    getent group ${VMAIL_GROUP} >/dev/null || groupadd -g ${VMAIL_UGID} ${VMAIL_GROUP} 2>/dev/null || true
    getent passwd ${VMAIL_USER} >/dev/null || useradd --system -g ${VMAIL_GROUP} -u ${VMAIL_UGID} ${VMAIL_USER} -d ${maildir} --create-home -s /sbin/nologin -c "virtual mail user" 2>/dev/null || true
    chown -R ${VMAIL_USER}:${VMAIL_GROUP} ${maildir}
}

set_postfix_mail_list() {
    local domain=${1}
    echo "****init postfix alias, Mailman, the GNU Mailing List Manager" | tee ${LOGFILE}
    postconf -e "alias_database = hash:${MAIL_LIST}"
    cat <<EOF>"${MAIL_LIST}"
postmaster: root
EOF
    postalias "${MAIL_LIST}"
    echo "****init postfix virtual domain alias, Email Redirect OK"
    postconf -e "virtual_alias_domains = ${domain}"
    postconf -e "virtual_alias_maps = hash:/etc/postfix/virtual"
    cat <<EOF |tee ${LOGFILE}>/etc/postfix/virtual
postmaster@${domain}  user2@${domain}
admin@${domain}       user1@${domain}
#@sample.com          catch-all@domain.com
EOF
    postmap /etc/postfix/virtual
}

set_postfix_ldap_local_recipient_map() {
    local ldap_srv=${1}
    local base=${2}
    echo "****Set Postfix local_recipient_map, so not local user can not post mails." | tee ${LOGFILE}
    echo "****Edit /etc/postfix/ldap-localusers.cf for ldap login info" | tee ${LOGFILE}
    postconf -e 'local_recipient_maps = ldap:/etc/postfix/ldap-localusers.cf unix:passwd.byname'
    cat <<EOF |tee ${LOGFILE} >/etc/postfix/ldap-localusers.cf
bind       = yes
bind_dn    = cn=readonly,${base}
bind_pw    = password
start_tls  = no
# tls_require_cert = off
# # #
server_host = ${ldap_srv}
server_port = 389
search_base = ${base}
# # #
query_filter = (&(uid=%u))
# query_filter = (&(uid=%u)(accountStatus=active))
result_attribute = uid
version = 3
EOF
    echo "****check postfix ldap local user, output: user1, -v verbose" | tee ${LOGFILE}
    postmap -q 'user1' ldap:/etc/postfix/ldap-localusers.cf || true
}

init_postfix() {
    local name=${1}
    local domain=${2}
    local maildir=${3}
    local cert=${4}
    local key=${5}
    echo "****reinit postfix" | tee ${LOGFILE}
    rm -f /etc/postfix/main.cf /etc/postfix/master.cf 2>/dev/null
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure postfix 2>/dev/null || true
    # postmap need main.cf config item. so execute here
    echo "$domain" > /etc/mailname

    postconf -e 'myorigin = /etc/mailname'
    postconf -e "smtpd_banner = ESMTP ${domain}"
    postconf -e "myhostname = ${name}.${domain}"
    postconf -e "mydomain = ${domain}"
    # postconf -e "setgid_group = postdrop"
    # postconf -e "sendmail_path = $(which sendmail)"
    # mailq_path = /usr/bin/mailq
    # message_size_limit = 10485760  # 限制单封邮件的最大长度
    # mailbox_size_limit = 20480000  # 单封邮件大小限制，单位字节
    # mail_owner = postfix           # postfix daemon 进程的运行身份
    postconf -e "mailbox_size_limit = 10485760"
    postconf -e 'inet_interfaces = all'
    postconf -e 'inet_protocols = ipv4'
    postconf -e 'mydestination = $mydomain, localhost.$mydomain, localhost'
    postconf -e 'alias_maps = '
    ####################
    postconf -e 'mailbox_transport = lmtp:unix:private/dovecot-lmtp'
    echo "****turn off local recipient checking in the Postfix SMTP server!!!!" | tee ${LOGFILE}
    postconf -e 'local_recipient_maps ='
    ####################
    postconf -e 'html_directory = no'
    #This is super important; we will only allow authenticated mail below.
    postconf -e 'smtpd_sasl_auth_enable = yes'
    postconf -e 'smtpd_sasl_type = dovecot'
    postconf -e 'smtpd_sasl_path = private/auth'
    postconf -e 'smtpd_sasl_security_options = noanonymous'
    postconf -e 'smtpd_sasl_tls_security_options = $smtpd_sasl_security_options'
    postconf -e 'smtpd_sasl_local_domain = $mydomain'
    postconf -e 'broken_sasl_auth_clients = yes'
    postconf -e 'smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination'
    #Authed clients can specify any destination domain.
    postconf -e 'smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination'
    postconf -e 'tls_medium_cipherlist = AES128+EECDH:AES128+EDH'
    postconf -e 'smtp_use_tls=yes'
    # the preceding line and this line make sure we're sending mail encrypted if possible
    postconf -e 'smtp_tls_security_level = may'
    # disable insecure protocols'
    postconf -e 'smtp_tls_mandatory_protocols = !SSLv2,!SSLv3,!TLSv1,!TLSv1.1'
    postconf -e 'smtp_tls_protocols=!SSLv2,!SSLv3,!TLSv1,!TLSv1.1'
    postconf -e 'smtp_tls_mandatory_ciphers = medium'
    postconf -e "smtp_tls_cert_file = ${cert}"
    postconf -e "smtp_tls_key_file = ${key}"
    postconf -e 'smtpd_use_tls=yes'
    # the preceding line and this line make sure mail coming in to us is encrypted if possible
    postconf -e 'smtpd_tls_security_level = may'
    postconf -e 'smtpd_tls_auth_only = yes'
    postconf -e 'smtpd_tls_mandatory_protocols = !SSLv2,!SSLv3,!TLSv1,!TLSv1.1'
    postconf -e 'smtpd_tls_protocols=!SSLv2,!SSLv3,!TLSv1,!TLSv1.1'
    postconf -e 'smtpd_tls_mandatory_ciphers = medium'
    postconf -e "smtpd_tls_cert_file = ${cert}"
    postconf -e "smtpd_tls_key_file = ${key}"
    postconf -e 'smtpd_tls_received_header = yes'
    postconf -e 'smtpd_tls_session_cache_timeout = 3600s'
    postconf -e 'tls_random_source = dev:/dev/urandom'

    # Enable SMTPS and MSA
    sed -i.orig.${TIMESPAN} -E \
        -e 's/^\s*#*submission\s*inet\s*.*/submission inet n   -   y   -   -   smtpd/g' \
        -e 's/^\s*#*smtps\s*inet\s*.*/smtps inet n   -   y   -   -   smtpd/g' \
        -e 's/^\s*#*\s*-o smtpd_tls_wrappermode=yes/  -o smtpd_tls_wrappermode=yes/g' \
        /etc/postfix/master.cf
}

set_dovecot_mailbox_ldap_auth() {
    local ldap_srv=${1}
    local base=${2}
    echo "****dovecot ldap auth" | tee ${LOGFILE}
    # auth_username_format = %Ln L:lowercase, n:drop @domain
    sed --quiet -i.orig.${TIMESPAN} -E \
        -e '/(auth_username_format\s*=|disable_plaintext_authi\s*=|auth_mechanisms\s*=|include\s+auth-system.conf.ext|include\s+auth-ldap.conf.ext).*/!p' \
        -e '$a#!include auth-system.conf.ext' \
        -e '$a!include auth-ldap.conf.ext' \
        -e '$adisable_plaintext_auth = no' \
        -e '$aauth_mechanisms = plain login' \
        -e '$aauth_username_format = %Ln' \
        /etc/dovecot/conf.d/10-auth.conf
    cat /etc/dovecot/conf.d/auth-ldap.conf.ext 2>/dev/null || true> /etc/dovecot/conf.d/auth-ldap.conf.ext.orig.${TIMESPAN} || true
    cat <<EOF |tee ${LOGFILE}> /etc/dovecot/conf.d/auth-ldap.conf.ext
passdb {
  driver = ldap
  args = /etc/dovecot/dovecot-ldap.conf.ext
}
userdb {
  driver = ldap
  args = /etc/dovecot/dovecot-ldap.conf.ext
}
EOF
    cat /etc/dovecot/dovecot-ldap.conf.ext 2>/dev/null || true > /etc/dovecot/dovecot-ldap.conf.ext.orig.${TIMESPAN}
    cat <<EOF |tee ${LOGFILE}>/etc/dovecot/dovecot-ldap.conf.ext
# dn                  = cn=readonly,${base}
# dnpass              = password

# if tls yes, ldap_srv must same as "ldap tls pem common name".
# add ldap_srv in /etc/hosts.
tls                 = no
tls_require_cert    = never

hosts               = ${ldap_srv}
# base = ou=People,dc=test,dc=mail
base                = ${base}
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
    echo "****dovecot passwd_file auth" | tee ${LOGFILE}
    # passwd file auth
    # ssl = required, client wants to use AUTH PLAIN is ok
    # auth_username_format = %Lu L:lowercase, u:whole user, include @domain
    sed --quiet -i.orig.${TIMESPAN} -E \
        -e '/(auth_username_format\s*=|disable_plaintext_authi\s*=|auth_mechanisms\s*=|include\s+auth-system.conf.ext|include\s+auth-passwdfile.conf.ext).*/!p' \
        -e '$a#!include auth-system.conf.ext' \
        -e '$a!include auth-passwdfile.conf.ext' \
        -e '$adisable_plaintext_auth = no' \
        -e '$aauth_mechanisms = plain login' \
        -e '$aauth_username_format = %Lu' \
        /etc/dovecot/conf.d/10-auth.conf
    cat /etc/dovecot/conf.d/auth-passwdfile.conf.ext 2>/dev/null > /etc/dovecot/conf.d/auth-passwdfile.conf.ext.orig.${TIMESPAN} || true
    cat <<EOF |tee ${LOGFILE}> /etc/dovecot/conf.d/auth-passwdfile.conf.ext
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
    cat /etc/dovecot/passwd 2>/dev/null > /etc/dovecot/passwd.orig.${TIMESPAN} || true
    cat <<EOF |tee ${LOGFILE}> /etc/dovecot/passwd
# doveadm pw -s SHA512-CRYPT -p password | cut -d '}' -f2
admin@${domain}:$(doveadm pw -s SHA512-CRYPT -p password | cut -d '}' -f2)
user1@${domain}:$(doveadm pw -s SHA512-CRYPT -p password | cut -d '}' -f2)
user2@${domain}:$(doveadm pw -s SHA512-CRYPT -p password | cut -d '}' -f2)
EOF
    chmod 600 /etc/dovecot/passwd
}

set_mailbox_autocreate() {
    echo "****dovecot mailbox autocreate" | tee ${LOGFILE}
    sed --quiet -i.orig.${TIMESPAN} -E \
        -e '/^namespace\s+inbox\s*\{/,/^\}/!p' \
        /etc/dovecot/conf.d/15-mailboxes.conf
    cat <<EOF |tee ${LOGFILE}>>/etc/dovecot/conf.d/15-mailboxes.conf
namespace inbox {
  mailbox Drafts {
    auto = subscribe
    special_use = \Drafts
  }
  mailbox Junk {
    auto = subscribe
    special_use = \Junk
  }
  mailbox Trash {
    auto = subscribe
    special_use = \Trash
  }
  mailbox Sent {
    auto = subscribe
    special_use = \Sent
  }
  mailbox "Sent Messages" {
    auto = subscribe
    special_use = \Sent
  }
}
EOF
}

init_dovecot() {
    local maildir=${1}
    local cert=${2}
    local key=${3}
    local domain=${4}
    echo "****reinit dovecot" | tee ${LOGFILE}
    rm -f /etc/dovecot/conf.d/* /etc/dovecot/* 2>/dev/null || true
    UCF_FORCE_CONFFMISS=1 DEBIAN_FRONTEND=noninteractive dpkg-reconfigure dovecot-core 2>/dev/null | true
    # Enable SSL
    sed --quiet -i.orig.${TIMESPAN} -E \
        -e '/^\s*(ssl\s*=|ssl_cert\s*=|ssl_key\s*=).*/!p' \
        -e '$assl = required' \
        -e "\$assl_cert = <${cert}" \
        -e "\$assl_key = <${key}" \
        /etc/dovecot/conf.d/10-ssl.conf
        # ssl_dh = </usr/share/dovecot/dh.pem
    sed --quiet -i.orig.${TIMESPAN} -E \
        -e '/^\s*(mail_location\s*=|mail_home\s*=|mail_access_groups\s*=|default_login_user\s*=).*/!p' \
        -e "\$amail_location = maildir:${maildir}/%d/%n" \
        -e "\$amail_home = ${maildir}/%n" \
        -e "\$amail_access_groups = ${VMAIL_GROUP}" \
        -e "\$adefault_login_user = ${VMAIL_USER}" \
        -e "\$amail_uid = ${VMAIL_UGID}" \
        -e "\$amail_gid = ${VMAIL_UGID}" \
        /etc/dovecot/conf.d/10-mail.conf

    sed --quiet -i.orig.${TIMESPAN} -E \
        -e '/^service\s+(auth|imap-login|pop3-login|lmtp)\s*\{/,/^\}/!p' \
        /etc/dovecot/conf.d/10-master.conf
    cat <<EOF |tee ${LOGFILE}>> /etc/dovecot/conf.d/10-master.conf
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

    postconf -e 'debug_peer_level = 2'
    postconf -e "debug_peer_list = ${domain}"

    sed --quiet -i.orig.${TIMESPAN} -E \
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
        --ldap     <ldap_srv>  ldap auth OR default password file
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        # test on debian bullseys!!
        apt -y install gnupg && wget -q -O- 'https://repo.dovecot.org/DOVECOT-REPO-GPG' |
            gpg --dearmor > /etc/apt/trusted.gpg.d/dovecot-archive-keyring.gpg
        apt -y install apt-transport-https
        echo "deb https://repo.dovecot.org/ce-2.3-latest/debian/bullseye bullseye main" >/etc/apt/sources.list.d/dovecot.list
        apt -y install postfix postfix-ldap dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-ldap
        # check ssl
        openssl s_client -servername mail.sample.org -connect mail.sample.org:pop3s
        # check starttls:
        openssl s_client -host mail.sample.org -port 25 -starttls smtp
        openssl s_client -host mail.sample.org -port 465 -starttls smtp
        openssl s_client -host mail.sample.org -port 110 -starttls pop3
        openssl s_client -host mail.sample.org -port 143 -starttls imap
        openssl s_client -host mail.sample.org -port 587 -starttls smtp
        postconf -a (SASL support in the SMTP server)
        postconf -A (SASL support in the SMTP+LMTP client)
        doveconf -a/postconf
        postfix check
        run test: doveadm auth test user1 password"
        user info: doveadm user user1"
        user login: doveadm auth login user1 password"
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
    local name="" domain="" maildir="" cert="" key="" ldap=""
    local opt_short=""
    local opt_long="name:,domain:,dir:,cert:,key:,ldap:,"
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
            --ldap)         shift; ldap=${1}; shift;;
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
    [ -z "${ldap}" ] && set_mailbox_password_auth "${maildir}" "${domain}"
    [ -z "${ldap}" ] || {
        local d1="" d2="" d3=""
        IFS='.' read -r d1 d2 d3 <<< "${domain}"
        set_postfix_ldap_local_recipient_map "${ldap}" "ou=People,dc=${d1}${d2:+,dc=${d2}}${d3:+,dc=${d3}}"
        set_dovecot_mailbox_ldap_auth "${ldap}" "ou=People,dc=${d1}${d2:+,dc=${d2}}${d3:+,dc=${d3}}"
        echo "**** modify: /etc/dovecot/dovecot-ldap.conf.ext" | tee ${LOGFILE}
        echo "****  hosts, base, tls, hosts -> USE DNS NAME(same as ldap PKI Sign cert DN)" | tee ${LOGFILE}
    }
    # set_debug "${domain}"
    echo "****ALL OK ${TIMESPAN}" | tee ${LOGFILE}
    return 0
}
main "$@"
