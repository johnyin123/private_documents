#!/usr/bin/env bash
echo $(hostname)
apt-get update
apt-get install -y postfix dovecot-common dovecot-pop3d dovecot-imapd mailutils

#chaing in main.cf
echo 'transport_maps = hash:/etc/postfix/transport' >> /etc/postfix/main.cf
# sed -i 's/.*inet_interfaces.*/inet_interfaces = all /' /etc/postfix/main.cf
# sed -i 's/.*inet_interfaces = localhost.*/#inet_interfaces = localhost /' /etc/postfix/main.cf

#changing in postfix file
touch /etc/postfix/aliases /etc/postfix/transport

# update aliases transport databases

postalias /etc/postfix/aliases
postmap /etc/postfix/transport
postmap hash:/etc/postfix/transport

# changing in dovecot confg file
#file path /etc/dovecot/conf.d/10-mail.conf

sed -i 's/.*mail_privileged.*/mail_privileged_group = mail /' /etc/dovecot/conf.d/10-mail.conf
sed -i 's/.*mail_location.*/mail_location = mbox:~\/mail:INBOX=\/var\/mail\/%u /' /etc/dovecot/conf.d/10-mail.conf

service dovecot restart
service postfix restart

echo 'For any error see log file\npath = /var/log/mail.log'

while true
do
	echo 'If you want to add new user press (y or n)'
	read choice
	if [ "$choice" = "y" ]
		then
			echo 'Enter New User name'
			read user
			echo 'Enter password'
			read password
            useradd --no-create-home -G mail --shell /usr/sbin/nologin ${user}
            echo "${user}:${password}" | chpasswd
            touch /var/mail/"$1"
            chown "$1":mail /var/mail/"$1"
			echo "'${user}:${password}' added successfully"
		else
			break
	fi
done
