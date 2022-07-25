# www.server-world.info
# postconf -e 'smtp_tls_security_level = may'

init_postfix mail.srv.world srv.world /mail cert key
init_postfix() {
    local name=${1}
    local domain=${2}
    local maildir=${3}
    local cert=${4:-}
    local key=${5:-}
    local keys=myhostname|mydomain|myorigin|inet_interfaces|inet_protocols|mydestination|mynetworks|home_mailbox|smtpd_banner|disable_vrfy_command|smtpd_helo_required|message_size_limit|smtpd_sasl_type|smtpd_sasl_path|smtpd_sasl_auth_enable|smtpd_sasl_security_options|smtpd_sasl_local_domain|smtpd_recipient_restrictions
    sed --quiet -i.orig -E \
        -e "/^\s*(${keys}).*/!p" \
        -e "\$amyhostname = ${name}" \
        -e "\$amydomain = ${domain}" \
        -e "\$ahome_mailbox = ${maildir}" \
        -e '$amyorigin = $mydomain' \
        -e '$ainet_interfaces = all' \
        -e '$ainet_protocols = ipv4' \
        -e '$amydestination = $myhostname, localhost.$mydomain, localhost, $mydomain' \
        -e '$amynetworks = 127.0.0.0/8, 10.0.0.0/24' \
        -e '$asmtpd_banner = $myhostname ESMTP' \
        -e '$adisable_vrfy_command = yes' \
        -e '$asmtpd_helo_required = yes' \
        -e '$amessage_size_limit = 10240000' \
        -e '# SMTP-Auth settings' \
        -e '$asmtpd_sasl_type = dovecot' \
        -e '$asmtpd_sasl_path = private/auth' \
        -e '$asmtpd_sasl_auth_enable = yes' \
        -e '$asmtpd_sasl_security_options = noanonymous' \
        -e '$asmtpd_sasl_local_domain = $myhostname' \
        -e '$asmtpd_recipient_restrictions = permit_mynetworks, permit_auth_destination, permit_sasl_authenticated, reject' \
        /etc/postfix/main.cf
    [ -z "${cert}" ] || [ -z "${key}" ] && return 0
    sed --quiet -i -E \
        -e '$asmtpd_use_tls = yes' \
        -e '$asmtp_tls_mandatory_protocols = !SSLv2, !SSLv3' \
        -e '$asmtpd_tls_mandatory_protocols = !SSLv2, !SSLv3' \
        -e "\$asmtpd_tls_cert_file = ${cert}" \
        -e "\$asmtpd_tls_key_file = ${key}" \
        -e '$asmtpd_tls_session_cache_database = btree:${data_directory}/smtpd_scache' \
        /etc/postfix/main.cf

#  [root@mail ~]# vi /etc/postfix/master.cf
# # line 17,18,20 : uncomment
# submission inet n       -       n       -       -       smtpd
#   -o syslog_name=postfix/submission
# #  -o smtpd_tls_security_level=encrypt
#   -o smtpd_sasl_auth_enable=yes
# 
# # line 29-32 : uncomment
# smtps     inet  n       -       n       -       -       smtpd
#   -o syslog_name=postfix/smtps
#   -o smtpd_tls_wrappermode=yes
#   -o smtpd_sasl_auth_enable=yes

}

init_dovecot() {
    local maildir=${1}
    # provide SASL function to Postfix.
    sed --quiet -i.orig -E \
        -e '/^\s*(disable_plaintext_auth|auth_mechanisms).*/!p' \
        -e '$adisable_plaintext_auth = no' \
        -e '$aauth_mechanisms = plain login' \
        /etc/dovecot/conf.d/10-auth.conf
    sed --quiet -i.orig -E \
        -e '/^\s*(mail_location).*/!p' \
        -e "\$amail_location = ${maildir}" \
        /etc/dovecot/conf.d/10-mail.conf
    sed --quiet -i.orig -E \
        -e '/^\s*(ssl).*/!p' \
        -e '$assl = yes' \
        /etc/dovecot/conf.d/10-ssl.conf
    sed --quiet -i.orig -E \
        -e '/^\s*unix_listener/,/\s*\}/!p' \
        -e '$a# Postfix smtp-auth'
        -e '$aunix_listener /var/spool/postfix/private/auth {'
        -e '$a\  mode = 0666'
        -e '$a\  user = postfix'
        -e '$a\  group = postfix'
        -e '$a}'
        /etc/dovecot/conf.d/10-master.conf
}
