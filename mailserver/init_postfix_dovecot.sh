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
VERSION+=("d8e83f1[2022-08-01T09:10:48+08:00]:init_postfix_dovecot.sh")
################################################################################
TIMESPAN=$(date '+%Y%m%d%H%M%S')
VMAIL_USER=${VMAIL_USER:-vmail}
VMAIL_GROUP=${VMAIL_GROUP:-vmail}
VMAIL_UGID=${VMAIL_UGID:-5000}
MAIL_LIST=${MAIL_LIST:-/etc/aliases}

init_vmail_user() {
    local maildir=${1}
    userdel -f -r ${VMAIL_USER} || true
    groupdel -f ${VMAIL_GROUP} || true
    getent group ${VMAIL_GROUP} >/dev/null || groupadd -g ${VMAIL_UGID} ${VMAIL_GROUP} 2>/dev/null || true
    getent passwd ${VMAIL_USER} >/dev/null || useradd --system -g ${VMAIL_GROUP} -u ${VMAIL_UGID} ${VMAIL_USER} -d ${maildir} --create-home -s /sbin/nologin -c "virtual mail user" 2>/dev/null || true
    chown -R ${VMAIL_USER}:${VMAIL_GROUP} ${maildir}
}

set_postfix_mail_list() {
    postconf -e "alias_database = hash:${MAIL_LIST}"
    cat <<EOF>"${MAIL_LIST}"
postmaster: root
demolst: admin@test2.domain, user1@test.domain
EOF
    postalias "${MAIL_LIST}"
}

init_postfix() {
    local name=${1}
    local domain=${2}
    local maildir=${3}
    local cert=${4}
    local key=${5}
    cat /etc/postfix/main.cf 2>/dev/null > /etc/postfix/main.cf.orig.${TIMESPAN} || true
    rm -f /etc/postfix/main.cf && touch /etc/postfix/main.cf
    # postmap need main.cf config item. so execute here
    echo "${domain}     OK" > /etc/postfix/vdomains
    postmap /etc/postfix/vdomains
    echo "$domain" > /etc/mailname

    postconf -e 'myorigin = /etc/mailname'
    postconf -e "smtpd_banner = ESMTP ${domain}"
    postconf -e "myhostname = ${name}.${domain}"
    postconf -e "mydomain = ${domain}"
    # postconf -e "setgid_group = postdrop"
    # postconf -e "sendmail_path = $(which sendmail)"
    #  mailq_path = /usr/bin/mailq
    # mail max size 10M
    postconf -e "mailbox_size_limit = 10485760"
    postconf -e 'inet_interfaces = all'
    postconf -e 'inet_protocols = ipv4'
    postconf -e 'mydestination = $myhostname, localhost.$mydomain, localhost'
    postconf -e 'alias_maps = '
    postconf -e "virtual_mailbox_base = ${maildir}"
    postconf -e 'home_mailbox = Maildir/'
    postconf -e 'virtual_mailbox_domains = hash:/etc/postfix/vdomains'
    # postconf -e 'virtual_mailbox_maps = hash:/etc/postfix/vmaps'
    postconf -e "virtual_minimum_uid = ${VMAIL_UGID}"
    postconf -e "virtual_uid_maps = static:${VMAIL_UGID}"
    postconf -e "virtual_gid_maps = static:${VMAIL_UGID}"
    # I'm glossing over this but LMTP is basically what we're using to send things over to Dovecot, this will be important because it allows Dovecot to do some processing on incoming mail later.
    postconf -e 'virtual_transport = lmtp:unix:private/dovecot-lmtp'
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

set_mailbox_password_auth() {
    local maildir=${1}
    local domain=${2}

    # passwd file auth
    # ssl = required, client wants to use AUTH PLAIN is ok
    sed --quiet -i.orig.${TIMESPAN} -E \
        -e '/(disable_plaintext_authi\s*=|auth_mechanisms\s*=|include\s+auth-system.conf.ext|include\s+auth-passwdfile.conf.ext).*/!p' \
        -e '$a#!include auth-system.conf.ext' \
        -e '$a!include auth-passwdfile.conf.ext' \
        -e '$adisable_plaintext_auth = no' \
        -e '$aauth_mechanisms = plain login' \
        /etc/dovecot/conf.d/10-auth.conf
    cat /etc/dovecot/conf.d/auth-passwdfile.conf.ext 2>/dev/null > /etc/dovecot/conf.d/auth-passwdfile.conf.ext.orig.${TIMESPAN} || true
    cat <<EOF > /etc/dovecot/conf.d/auth-passwdfile.conf.ext
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
    cat <<EOF > /etc/dovecot/passwd
# doveadm pw -s SHA512-CRYPT -p password | cut -d '}' -f2
admin@${domain}:$(doveadm pw -s SHA512-CRYPT -p password | cut -d '}' -f2)
user1@${domain}:$(doveadm pw -s SHA512-CRYPT -p password | cut -d '}' -f2)
user2@${domain}:$(doveadm pw -s SHA512-CRYPT -p password | cut -d '}' -f2)
EOF
    chmod 600 /etc/dovecot/passwd
}

set_mailbox_autocreate() {
    sed --quiet -i.orig.${TIMESPAN} -E \
        -e '/^namespace\s+inbox\s*\{/,/^\}/!p' \
        /etc/dovecot/conf.d/15-mailboxes.conf
    cat <<EOF >>/etc/dovecot/conf.d/15-mailboxes.conf
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
        /etc/dovecot/conf.d/10-mail.conf

    sed --quiet -i.orig.${TIMESPAN} -E \
        -e '/^service\s+(auth|imap-login|pop3-login|lmtp)\s*\{/,/^\}/!p' \
        /etc/dovecot/conf.d/10-master.conf
    cat <<EOF >> /etc/dovecot/conf.d/10-master.conf
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
        apt -y install postfix dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd
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
EOF
    exit 1
}

# testsaslauthd -u user1 -p password -f /var/spool/postfix/var/run/saslauthd/mux
# saslfinger -s
main() {
    local name="" domain="" maildir="" cert="" key=""
    local opt_short=""
    local opt_long="name:,domain:,dir:,cert:,key:,"
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
    set_postfix_mail_list
    init_dovecot "${maildir}" "${cert}" "${key}" "${domain}"
    set_mailbox_autocreate
    set_mailbox_password_auth "${maildir}" "${domain}"
    # set_debug "${domain}"
    echo "ALL OK ${TIMESPAN}"
    return 0
}
main "$@"
