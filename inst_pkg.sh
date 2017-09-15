#!/bin/bash

#/etc/adjtime/UTC == > LOCAL
#--->创建swap
#dd if=/dev/zero of=/swapfile bs=1M count=512 && chmod 600 /swapfile && mkswap /swapfile
#sed -i '$a\/swapfile swap swap defaults 0 0' /etc/fstab
#sed -i '$anone \/tmp	tmpfs	defaults	0	0' /etc/fstab

# gnokii-smsd  : SMS Daemon for mobile phones NOKIA~~~
# dpkg-reconfigure console-setup
# openshot 视频编辑器
# gameconqueror 游戏作弊工具like CheatEngine
# wvdial
# poppler-data for chinese font display for epdfview!!
# "epdfview poppler-data" replaced by foxitreader
# compiz --replace --sm-disable --ignore-desktop-hints ccp 
# ibus="ibus ibus-pinyin ibus-qt4 ibus-gtk"
# mirage(picviewer), replaced by ristretto
# file-roller replaced by squeeze
# mp3 tag encoder: mid3iconv -e GBK *.mp3

ROOT_UID=0
if [ "$UID" -ne "$ROOT_UID" ]
then 
	echo "Must be root to run this script." 
	exit 1
fi


SUCCESS=0 
function checkInst()
{
	item=$1
	#printf "hello %.5s\n" message
	apt-get -y --force-yes install ${item} || { echo "ERROR Install " ${item}; read line1; }
}
#sniffer="valgrind dia"
#desk3d="compiz compiz-fusion-plugins-extra compiz-fusion-plugins-main compiz-fusion-bcop compizconfig-settings-manager cairo-dock-compiz-icon-plugin"
#others="qbittorrent"

tools="p7zip-full arj zip mscompress unar eject bc less vim ftp telnet nmap tftp ntpdate screen lsof strace ltrace parallel lftp"

# xdesktop="lxde-core lxappearance lxrandr lxmusic fonts-droid-fallback xserver-xorg gnome-icon-theme lightdm va-driver-all vdpau-va-driver wpasupplicant xarchiver xdg-utils"
xdesktop="xarchiver fonts-droid-fallback xserver-xorg xfce4 xfce4-terminal xfce4-screenshooter xfburn xdm gnome-icon-theme isomaster"
# thunar-archive-plugin 
# lightdm / xdm
editor="galculator vim-gtk medit rdesktop xvnc4viewer filezilla claws-mail claws-mail-i18n claws-mail-tnef-parser claws-mail-fancy-plugin"
# amule-daemon 
xtools="wireshark gpaint stardict-gtk iptux xscreensaver qt4-qtconfig wicd-gtk fbreader mpv smplayer libqt4-opengl"
chineseinput="fcitx-ui-classic fcitx-tools fcitx fcitx-sunpinyin sunpinyin-utils fcitx-config-gtk"
mediatools="alsa-utils dkms python-mutagen highlight ctags bison byacc gawk gperf sqlite3 lemon squashfs-tools"
#winpdb python debugger, spe python ide
develops="libstdc++5 pkg-config flex elfutils unifdef astyle indent cxref ccache gettext poedit gdb cppcheck build-essential graphviz intltool winpdb spe"
developpkg="manpages-dev manpages-posix manpages-posix-dev libsqlite3-dev manpages "

fssupport="genisoimage fusesmb smbclient ntfs-3g sshfs ecryptfs-utils mtools dosfstools openssh-client sshpass openssh-server kpartx"
nettools="tcpdump iperf ethtool wireless-tools pppoe nbtscan ipvsadm"
curlpkg="rpm aria2 axel curl mpg123 jp2a nmon sysstat arping conky-all libnotify-bin inotify-tools dnsutils"
firmware="firmware-realtek firmware-linux-nonfree firmware-linux-free"
checkInst "${tools} ${xdesktop} ${editor} ${xtools} ${chineseinput} ${mediatools} ${develops} ${fssupport} ${nettools} ${curlpkg} ${firmware} ${developpkg}"

#date '+%Y %m %d %H'|xargs lunar --utf8 阴历 lunar --big5 $(date '+%Y %m %d') |iconv -f big5
#desktopsearch="strigi-daemon strigi-utils strigi-client"
othertools="minicom socat aoetools lunar sysstat"
games="gnudoq pcsxr git git-flow subversion"
androidtool="usb-modeswitch usbip vblade jmtpfs android-tools-adb android-tools-fastboot"
checkInst "${desktopsearch} ${androidtool} ${games} ${othertools}"

apt-get -y --force-yes install libc6-i386 rar google-chrome-stable qpdfview gpicview txt2regex shellcheck
apt-get install w64codecs
#markdown editor
apt install retext
#  PDFREADER=FoxitReader_1.1.0_i386.deb
#  if [ -f "$PDFREADER" ]; then
#  dpkg --add-architecture i386
#  apt-get update
#  apt-get install libgtk2.0-0:i386 libstdc++6:i386
#  dpkg -i --force-architecture $PDFREADER
#  fi

#for mtk kernel-tool
# apt-get -y --force-yes install libswitch-perl

apt-get upgrade -y --force-yes
removepkg="tango-icon-theme fonts-liberation"
apt-get remove ${removepkg} --purge
apt-get autoremove --purge -y --force-yes


touch /etc/apt-fast.conf

echo "install vimrc.local? Y/n"
read YesNo
if [ ${YesNo:-N} = "Y" ] || [ ${YesNo:-N} = "y" ]
then
cat << EOF > /etc/vim/vimrc.local
syntax on
" color evening
set number
set nowrap
set fileencodings=utf-8,gb2312,gbk,gb18030
" set termencoding=utf-8
let &termencoding=&encoding
set fileformats=unix
set hlsearch                    " highlight the last used search pattern
set noswapfile
set tabstop=4                " 设置tab键的宽度
set shiftwidth=4             " 换行时行间交错使用4个空格
set expandtab                " 用space替代tab的输入
set autoindent               " 自动对齐
set backspace=2              " 设置退格键可用
set cindent shiftwidth=4     " 自动缩进4空格
set smartindent              " 智能自动缩进
set mouse=""
filetype plugin on
"Paste toggle - when pasting something in, don't indent.
set pastetoggle=<F7>
EOF
fi

echo "install gvimrc.local? Y/n"
read YesNo
if [ ${YesNo:-N} = "Y" ] || [ ${YesNo:-N} = "y" ]
then
cat << EOF > /etc/vim/gvimrc.local
set fileencodings=utf-8,gb2312,gbk,gb18030,
set fileformats=unix
set tabstop=4
set imcmdline
set guifont=DejaVu\ Sans\ Mono\ 14
EOF
fi


echo "install tools? Y/n"
read YesNo
if [ ${YesNo:-N} = "Y" ] || [ ${YesNo:-N} = "y" ]
then
	for tool in cfg-doc/tools/*
	do
		echo "install =========================== " ${tool} " =============================="
		cp ${tool} /usr/bin/
		chmod 755 /usr/bin/`basename ${tool}`
	done
fi

echo "install star dict? Y/n"
read YesNo
if [ ${YesNo:-N} = "Y" ] || [ ${YesNo:-N} = "y" ]
then
	LS=`ls cfg-doc/star-dict/*.bz2`
	DIC="/usr/share/stardict/dic"
	for i in $LS
	do
		echo $i
		tar xvfj $i -C $DIC
	done
fi

cat << EOF >> /etc/bash.bashrc

export HISTTIMEFORMAT='%F %T '
export HISTSIZE="10000"
# export PS1="\[\033[1;31m\]\u\[\033[m\]@\[\033[1;32m\]\h:\[\033[33;1m\]\w\[\033[m\]\$"
# export readonly PROMPT_COMMAND='{ msg=\$(history 1 | { read x y; echo \$y; });user=\$(whoami); echo \$(date "+%Y-%m-%d%H:%M:%S"):\$user:`pwd`/:\$msg ---- \$(who am i); } >> \$HOME/.history.'
source /usr/lib/git-core/git-sh-prompt
export GIT_PS1_SHOWDIRTYSTATE=1
export readonly PROMPT_COMMAND='{ msg=\$(history 1 | { read x y; echo \$y; });user=\$(whoami); echo \$(date "+%Y-%m-%d%H:%M:%S"):\$user:\$(pwd):\$msg ---- \$(who am i); } >> \$HOME/.history.; __git_ps1 "\\[\\033[1;31m\\]\\u\\[\\033[m\\]@\\[\\033[1;32m\\]\\h:\\[\\033[33;1m\\]\\w\\[\\033[m\\]" "\\\\\\\$ "'
set -o vi
EOF
echo "git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --""
echo "Chante mail sendto use claws-mail? Y/n"
read YesNo
if [ ${YesNo:-N} = "Y" ] || [ ${YesNo:-N} = "y" ]
then
	cat << EOF > /usr/share/Thunar/sendto/thunar-sendto-email.desktop
[Desktop Entry]
Type=Application
Version=1.0
Encoding=UTF-8
Name=Mail Recipient
Name[en_GB]=Mail Recipient
Name[zh_CN]=发邮件
Name[zh_TW]=郵件收據
Icon=internet-mail
Exec=claws-mail --attach %f
#Exec=/usr/lib/thunar/thunar-sendto-email %U
EOF
fi


echo "change alsa-asound config? Y/n"
read YesNo
if [ ${YesNo:-N} = "Y" ] || [ ${YesNo:-N} = "y" ]
then
	cat << EOF >> /var/lib/alsa/asound.state
pcm.asymed {
	type asym
	playback.pcm dmix
	capture.pcm dsnoop
}
pcm.default {
	type plug
	slave.pcm asymed
}
pcm.dmix {
	type dmix
	ipc_key 5678293
	ipc_key_add_uid yes
	slave {
		pcm 'hw:0,0'
		period_time 0
		period_size 128
		buffer_size 2048
		format S16_LE
		rate 48000
	}
}
pcm.dsnoop {
	type dsnoop
	ipc_key 5778293
	ipc_key_add_uid yes
	slave {
		pcm 'hw:0,0'
		period_time 0
		period_size 128
		buffer_size 2048
		format S16_LE
		rate 48000
	}
}
EOF
fi

echo "change ssh config? Y/n"
read YesNo
if [ ${YesNo:-N} = "Y" ] || [ ${YesNo:-N} = "y" ]
then
	cat << EOF >> /etc/ssh/ssh_config
#多条连接共享
ControlMaster auto
ControlPath /tmp/ssh_mux_%h_%p_%r
EOF
cat <<EOF >> /etc/ssh/sshd_config
MaxAuthTries 3
#登录次数
UseDNS no
EOF
fi

echo "add user[johnyin] to sudoers? Y/n"
read YesNo
if [ ${YesNo:-N} = "Y" ] || [ ${YesNo:-N} = "y" ]
then
	echo "johnyin ALL = NOPASSWD: ALL" >> /etc/sudoers
	echo "Defaults       logfile=/var/log/sudo.log">>/etc/sudoers
	visudo -c
fi

echo "change sources.list? Y/n"
read YesNo
if [ ${YesNo:-N} = "Y" ] || [ ${YesNo:-N} = "y" ]
then
cat << EOF > /etc/apt/sources.list
# deb http://192.168.175.25:8000 jessie main
# cross-development toolchains
# deb http://www.emdebian.org/debian jessie main

deb http://ftp.cn.debian.org/debian jessie main non-free contrib
deb http://ftp.cn.debian.org/debian jessie-proposed-updates main non-free contrib
deb http://ftp.cn.debian.org/debian-security jessie/updates main contrib non-free
#deb http://ftp.cn.debian.org/debian-multimedia jessie main non-free

#deb http://dl.google.com/linux/chrome/deb/ stable main
EOF
fi
#sed -i "s/UTC=yes/UTC=no/g" /etc/default/rcS 
sed -i "s/AutoMount=true/AutoMount=false/g" /usr/share/gvfs/mounts/network.mount

echo "BUG Repair PSMOUSE Y/n"
read YesNo
if [ ${YesNo:-N} = "Y" ] || [ ${YesNo:-N} = "y" ]
then
cat <<EOF > /etc/modprobe.d/trackpoint-elantech.conf
options psmouse proto=bare
EOF
fi

if [[ -f "/etc/X11/app-defaults/XTerm" ]]
then
cat << EOF >> /etc/X11/app-defaults/XTerm
xterm*faceName: DejaVu Sans Mono:antialias=True:pixelsize=16
xterm*faceNameDoublesize: Droid Sans Fallback:pixelsize=16
EOF
fi

echo "enable Sysstat(/var/log/sa/) crontab"
sed -i "s/ENABLED=\".*\"/ENABLED=\"true\"/g" /etc/default/sysstat
###########################################################
cd /usr/share/man && find ./ -maxdepth 1 -type d | tail -n +2 | grep -E -v '(en|zh|man).*' |while read d; do rm -rf $d; done

cd /usr/share/vim/vim80/lang && ln -s menu_zh_cn.utf-8.vim menu_zh_cn.utf8.vim

apt install pandoc
