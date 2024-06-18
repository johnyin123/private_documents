#!/bin//bash
# SPDX-License-Identifier: GPL-2.0
#	Copyright (c) 2020-2023 Devmfc
#	Setup multiboot loading of bootscript by u-boot bootloader.
#
set -Eeu

DEFAULT_BOOT_ORDER="sd usb emmc org"
BOOT_SCRIPT_ORDER="bootscript cfgload s905_autoscript boot.scr "

exit_with_message() {
	local errmsg=${1:-'Error occured, exitting...'}
	echo -e "[Error]\n$errmsg"
	exit 1
}

echo -e "Setup multiboot. This will reconfigure your bootloader environment to use a 'boot order' to load boot scripts while booting. The default boot order will be set to: \n1. sd, \n2. usb, \n3. emmc, \n4. original boot.\n"
echo "This will change your bootloader environment. By doing so there is always a small risk to 'brick' your box. If you don't have the tools, image and knowledge to fix that, you should reconsider. Personally I have never 'bricked' a box with this script. However ymmv, don't blame me."
read -p "Are you sure to proceed? y/N" answer;

if [[ ! ${answer} =~ ^[yY]$ ]]; then
	echo "Bye"
	exit 0
fi

echo "Ok, proceeding"

if ! fw_printenv -V > /dev/null; then
	echo -n "Installing libubootenv-tool... "
	apt-get install libubootenv-tool -yy || exit_with_message
	echo "[Ok]"
fi

echo -n "Trying to config u-boot environment storage location... "

fw_env_config=$(/usr/lib/u-boot-meson64/aml-find-uboot-env.sh) || {
	echo -e "\n[Error]\nCould not find a valid u-boot environment storage location."
	echo "This means that modification of bootloader environment is not possible."
	echo "In more than 80% of the cases this is caused by the presence of non-stock u-boot bootloader. Did you flash some other firmware to eMMC?"
	echo "Please install stock Android firmware and try again."
	
	exit 1
}

echo "${fw_env_config}" > /etc/fw_env.config
echo "[Ok]"

if [[ ! -f uboot-env.bak ]]; then
	echo -n "Backupping current u-boot environment to uEnv.bak... "
	fw_printenv > uEnv.bak || exit_with_message "Could not read u-boot environment!"
	echo "[Ok]"
fi

echo "Writing boot commands to bootloader... "

fw_setenv	cmd_make_compat		'cmd_read="fatload ${devtype} ${devnum}:${distro_bootpart}"; device=${devtype};devnr=${devnum};partnr=${distro_bootpart};partnum=${distro_bootpart};autoscript_source=${devtype}' || exit_with_message "fw_setenv"
fw_setenv 	cmd_bootsript_load	'for scrpt in "${boot_script_order}"; do fatload ${devtype} ${devnum}:${distro_bootpart} ${loadaddr} ${scrpt} && run cmd_make_compat && autoscr ${loadaddr}; done;' || exit_with_message "fw_setenv"
fw_setenv 	cmd_boot_emmc  		'setenv devtype mmc; setenv devnum 1; for partnum in "${boot_emmc_parts}"; do setenv distro_bootpart ${partnum}; run cmd_bootsript_load; done' || exit_with_message "fw_setenv"
fw_setenv 	cmd_boot_sd  		'if mmcinfo; then setenv devtype mmc; setenv devnum 0; setenv distro_bootpart 1; run cmd_bootsript_load; fi' || exit_with_message "fw_setenv"
fw_setenv 	cmd_boot_usb 		'if usb storage; then ; else usb start; fi; setenv devtype usb; setenv distro_bootpart 1; for devnum in "0 1 2 3"; do setenv devnum ${devnum}; run cmd_bootsript_load; done' || exit_with_message "fw_setenv"
fw_setenv 	cmd_boot_get_order	'boot_order="${default_boot_order}"; if test "${onetime_boot_order}" != "" ; then boot_order=${onetime_boot_order}; setenv onetime_boot_order; saveenv; fi; if test "${bootfromnand}" = "1"; then setenv bootfromnand 0; saveenv; boot_order="org ${boot_order}"; fi; echo "resulting boot_order:${boot_order}";'  || exit_with_message "fw_setenv"

# boot cmd for Coreelec in "ceemmc dual bootmode". You should add "ceemmc" to bootorder
#fw_setenv 	cmd_boot_ceemmc	'for partnum in "17 16 15 14"; do setenv cmd_read "fatload mmc 1:${partnum}"; if ${cmd_read} ${loadaddr} "cfgload"; then setenv device mmc; setenv devnr 1; setenv partnr ${partnum}; setenv ce_on_emmc "yes"; autoscr ${loadaddr}; fi; done'  || exit_with_message "fw_setenv"

fw_setenv default_boot_order "${DEFAULT_BOOT_ORDER}"  || exit_with_message "fw_setenv"
fw_setenv boot_script_order "${BOOT_SCRIPT_ORDER}"  || exit_with_message "fw_setenv"
fw_setenv boot_emmc_parts "1 2 1c 1b"  || exit_with_message "fw_setenv"

if ! fw_printenv |grep -E "^cmd_boot_org="; then
	fw_setenv cmd_boot_org "$(fw_printenv) -n bootcmd)"  || exit_with_message "Error backupping original bootcmd"
fi

fw_setenv bootcmd	 'run cmd_boot_get_order; for var in "${boot_order}"; do run cmd_boot_${var}; done; run cmd_boot_org'  || exit_with_message "fw_setenv"
echo "Done."
