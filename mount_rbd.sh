#! /bin/bash

function versioninfo
{
	VERSION="$Revision$"
	VERSION="${VERSION%\ \$}"; VERSION="${VERSION#\:}"; VERSION="${VERSION##\ }"
	VERSION="(CVS revision $VERSION)"

	NAME="$Name$"
	NAME="${NAME%\ \$}"; NAME="${NAME#\:}"; NAME="${NAME##\ }"; NAME="${NAME##release-}"; NAME="${NAME//-/.}"
	[[ -n $NAME ]] && NAME="Version $NAME "

	echo ${CMDNAME}
	echo ${NAME}${VERSION}

	echo -e "\nCopyright (C) 2013 Hacking Networked Solutions"
	echo "License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>."
	echo "This is free software: you are free to change and redistribute it."
	echo "There is NO WARRANTY, to the extent permitted by law."
}

function helpscreen
{
	echo "Usage: ${CMDNAME} <src> <dst> -o <opt>"
	echo "Mounts the Rados Block Device (RBD) specified by <src> at the mount point"
	echo "specified by <dst> using the mount options specified in <opt>"
	echo
	echo "    <src> describes an RBD volume:  pool/rbd"
	echo "    <dst> describes a mount point:  /mnt/data"
	echo
	echo "    <opt> describes the filesystem and mount options:  ext4:defaults"
	echo
	echo "    --help       display this help and exit"
	echo "    --version    output version information and exit"
}

function error_exit
{
	echo $1
	echo
	exit $2
}

function wait_for_device
{
	local limit=30
	while [[ ! -e $1 && $limit -gt 0 ]]; do
		limit=$((limit-1))
		sleep 0.5
	done
	[[ ! -e $1 ]] && error_exit "Device node $1 never appeared!"
}

# Check our inputs.
[[ -z $1 ]] && error_exit "Missing <src> - we need to know what to mount!"
[[ -z $2 ]] && error_exit "Missing <dst> - we need to know where to mount it!"
[[ -z $3 ]] && error_exit "Expected -o <opt>, got nothing!"
[[ $3 != "-o" ]] && error_exit "Expected -o <opt>, got something else!"
[[ -z $4 ]] && error_exit "Missing <opt> - we need to know how you want it mounting!"

# Validate our inputs.
[[ $1 == /* ]] && error_exit "RBD specifiers do NOT start with a /"
rbd_info=(${1//\// })
[[ ${#rbd_info[@]} != 2 ]] && error_exit "RBD should be specified as pool/device"
[[ ! -d $2 ]] && error_exit "Mount point [$4] does not exist!"

# If the RBD is not mapped already (we can't unmap in on unmount so it could be)...
if [[ ! -e /dev/rbd/${rbd_info[0]}/${rbd_info[1]} ]]; then
	# Try to map the RBD.
	rbd map ${rbd_info[1]} --pool ${rbd_info[0]} || \
		error_exit "Unable to mount RBD device \"${rbd_info[1]}\" from pool \"${rbd_info[0]}\""

	# We need to wait for UDEV to settle.
	wait_for_device /dev/rbd/${rbd_info[0]}/${rbd_info[1]}
fi

# Try to run fsck on the device as the init script won't!
fsck -M -C -T /dev/rbd/${rbd_info[0]}/${rbd_info[1]} -- -a || \
	echo "fsck of /dev/rbd/${rbd_info[0]}/${rbd_info[1]} returned with $?!"

# Try to mount the device, if it fails then unmap it and bail.
if ! mount /dev/rbd/${rbd_info[0]}/${rbd_info[1]} $2 -o $4; then
	rbd unmap /dev/rbd/${rbd_info[0]}/${rbd_info[1]}
	error_exit "Mounting device /dev/rbd/${rbd_info[0]}/${rbd_info[1]} at $2 failed!"
fi

# We're done!
exit 0
