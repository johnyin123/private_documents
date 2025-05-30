#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit

# Execution variables
OBJECT="${1}"
OPERATION="${2}"
ACTION="${3}"
XML="/etc/libvirt/qemu/${OBJECT}.xml"

# Log debug information to file
function debug {
  echo "[HOOK] ${1}" >> "/var/log/libvirt/qemu/${OBJECT}.log"
}

# Check if file exists
# We check this to avoid qemu hooks on other objects that are not VMs
if [ ! -f "${XML}" ]; then
  debug "VM object not detected, skipping"
  exit 0
fi

VMF="/tmp/vfio-${OBJECT}"
OPTIONS=$(grep -oPm1 "(?<=<description>)[^<]+" "${XML}")

#################################
### ==== Display Manager ==== ###
#################################

# Detect and stop the running display manager on host, when available
function stop_display_manager {

  managers=("sddm" "gdm" "lightdm" "lxdm" "xdm" "mdm" "display-manager")
  for manager in "${managers[@]}"; do

    if [ -x "$(command -v systemctl)" ]; then
      if systemctl is-active --quiet "${manager}.service"; then
        debug "Stopping ${manager} display service"
        echo "${manager}" >> "${VMF}-display-manager"
        systemctl stop "${manager}.service"
        sleep "2"
      fi
      while systemctl is-active --quiet "${manager}.service"; do
        debug "Waiting for ${manager} display service to stop"
        sleep "2"
      done
    fi

  done

}

# Restore the previously detected host display manager
function restore_display_manager {

  if [ -f "${VMF}-display-manager" ]; then
    while read -r manager; do
      if [ -x "$(command -v systemctl)" ]; then
        sleep "2"
        debug "Starting ${manager} display service again"
        systemctl start "${manager}.service"
      fi
    done < "${VMF}-display-manager"
  fi

}

#################################
### ======= VTConsole ======= ###
#################################

# Unbind consoles on host
function unbind_consoles {

  for (( i = 0; i < 16; i++)); do
    if [ -x "/sys/class/vtconsole/vtcon${i}" ]; then
      value=$(cat "/sys/class/vtconsole/vtcon${i}/name")
      if [ "$(echo "${value}" | grep -c "frame buffer")" = "1" ]; then
        debug "Unbinding console number ${i}"
        echo "0" > "/sys/class/vtconsole/vtcon${i}/bind"
        echo "${i}" >> "${VMF}-bound-consoles"
      fi
    fi
  done

}

# Rebind previously detected bound consoles on host
function rebind_consoles {

  if [ -f "${VMF}-bound-consoles" ]; then
    while read -r number; do
      if [ -x "/sys/class/vtconsole/vtcon${number}" ]; then
        value=$(cat "/sys/class/vtconsole/vtcon${number}/name")
        if [ "$(echo "${value}" | grep -c "frame buffer")" = "1" ]; then
          debug "Rebinding console number ${number}"
          echo "1" > "/sys/class/vtconsole/vtcon${number}/bind"
        fi
      fi
    done < "${VMF}-bound-consoles"
  fi

}

#################################
### ====== Framebuffer ====== ###
#################################

# Unbind framebuffer on host
function unbind_framebuffer {

  if [ -f /proc/fb ] && [ -n "$(cat /proc/fb)" ]; then
    debug "Unbinding framebuffer"
    echo "1" > "${VMF}-bound-framebuffer"
    echo "efi-framebuffer.0" > /sys/bus/platform/drivers/efi-framebuffer/unbind
  fi

}

# Rebind previouly detected framebuffer on host
function rebind_framebuffer {

  if [ -f "${VMF}-bound-framebuffer" ]; then
    debug "Rebinding framebuffer"
    echo "efi-framebuffer.0" > /sys/bus/platform/drivers/efi-framebuffer/bind
  fi

}

##################################
## ======= GPU Devices ======= ###
##################################

# Release GPU to be used by VFIO
function release_gpu {

  # Special case for main GPU
  [ "${1}" == "main" ] && stop_display_manager
  [ "${1}" == "main" ] && unbind_consoles
  [ "${1}" == "main" ] && unbind_framebuffer

  # Extract data and set config info
  vga="/sys/bus/pci/devices/0000:${2}"
  audio="/sys/bus/pci/devices/0000:${3}"
  driver=$(basename $(readlink "${vga}/driver"))
  mixer=$(basename $(readlink "${audio}/driver"))

  # Fix AMD GPU reset method
  if [ "${driver}" == "amdgpu" ] && [ "${4}" == "reset" ]; then
    debug "Applying device_specific reset method for AMD GPUs"
    echo "device_specific" > "${vga}/reset_method"
    echo "device_specific" > "${audio}/reset_method"
  fi

  # Unbind vga and audio from host
  if [ -n "${driver}" ] && [ "${driver}" != "pcieport" ]; then
    debug "Unbinding VGA ${2} from host driver: ${driver}"
    echo "0000:${2}" > "/sys/bus/pci/drivers/${driver}/unbind"
    echo "${driver}" > "${VMF}-${1}-gpu-driver"
  fi

  if [ -n "${mixer}" ] && [ "${mixer}" != "pcieport" ]; then
    debug "Unbinding audio ${3} from host driver: ${mixer}"
    echo "0000:${3}" > "/sys/bus/pci/drivers/${mixer}/unbind"
    echo "${mixer}" > "${VMF}-${1}-gpu-mixer"
  fi

  # Bind to VFIO
  debug "Binding GPU ${1} to VFIO"
  virsh nodedev-detach "pci_0000_${2//[:.]/_}"
  virsh nodedev-detach "pci_0000_${3//[:.]/_}"

}

# Restore GPU to the system
function restore_gpu {

  # Unbind vga and audio from VFIO
  debug "Reataching GPU ${1} to host"
  virsh nodedev-reattach "pci_0000_${2//[:.]/_}"
  virsh nodedev-reattach "pci_0000_${3//[:.]/_}"

  # Check for drivers and bind again if necessary
  vga="/sys/bus/pci/devices/0000:${2}"
  audio="/sys/bus/pci/devices/0000:${3}"

  if [ -f "${VMF}-${1}-gpu-driver" ] && [ ! -d "${vga}/driver" ]; then
    driver=$(cat ${VMF}-${1}-gpu-driver)
    debug "Binding VGA driver to ${2}: ${driver}"
    echo "0000:${2}" > "/sys/bus/pci/drivers/${driver}/bind"
  fi

  if [ -f "${VMF}-${1}-gpu-mixer" ] && [ ! -d "${audio}/driver" ]; then
    mixer=$(cat ${VMF}-${1}-gpu-mixer)
    debug "Binding audio driver to ${3}: ${mixer}"
    echo "0000:${3}" > "/sys/bus/pci/drivers/${mixer}/bind"
  fi

  # Special case for main GPU
  [ "${1}" == "main" ] && restore_display_manager
  [ "${1}" == "main" ] && rebind_consoles
  [ "${1}" == "main" ] && rebind_framebuffer

}

##################################
### == CPU Scaling Governor == ###
##################################

# Set CPU scaling governor to user defined mode
function set_cpu_scaling_governor {

  for index in `find /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort -V`; do
    debug "Scaling CPU governor to ${1} mode in core number ${index//[^0-9]/}"
    cat "${index}" >> "${VMF}-scaling-governor"
    echo "${1}" > "${index}"
  done

}

# Restore previously detected CPU scaling governor
function restore_cpu_scaling_governor {

  if [ -f "${VMF}-scaling-governor" ]; then
    index=0
    while read -r scaling; do
      debug "Restoring scaling CPU governor mode to ${scaling} in core number ${index}"
      echo "${scaling}" > "/sys/devices/system/cpu/cpu${index}/cpufreq/scaling_governor"
      ((index=index+1))
    done < "${VMF}-scaling-governor"
  fi

}

##################################
### === CPU Cores / Pinning === ##
##################################

# Preserve CPU cores by pinning the usage of some specific cores
function preserve_cpu_cores {

  if [ -x "$(command -v systemctl)" ]; then
    debug "Pinning CPU to use only the cores ${1}"
    echo "1" > "${VMF}-cpu-pinning"
    systemctl set-property --runtime -- user.slice AllowedCPUs="${1}"
    systemctl set-property --runtime -- system.slice AllowedCPUs="${1}"
    systemctl set-property --runtime -- init.scope AllowedCPUs="${1}"
  fi

}

# Restore previously detected CPU pinning on host
function restore_cpu_cores {

  if [ -s "${VMF}-cpu-pinning" ]; then
    debug "Restoring CPU pinning to use all cores"
    systemctl set-property --runtime -- user.slice AllowedCPUs=""
    systemctl set-property --runtime -- system.slice AllowedCPUs=""
    systemctl set-property --runtime -- init.scope AllowedCPUs=""
  fi

}

##################################
### ======= USB Devices ======= ##
##################################

# Watch and attach USB devices to VM
function attach_usb_device {
  debug "Added USB device to live passthrough: ${1}"
  echo "${1}" >> "${VMF}-usb-watch"
}

##################################
### ======= QEMU Hooks ======= ###
##################################

# On prepare begin qemu hook
function on_prepare_begin {

  for i in "$@"; do
    case $i in
      # Enable live GPU passthrough
      --gpu-passthrough=*)
        info=($(echo "${i#*=}" | tr ',' ' '))
        release_gpu "${info[@]}"
        shift
        ;;
      # Set CPU scaling governor mode
      --cpu-scaling-mode=*)
        mode="${i#*=}"
        set_cpu_scaling_governor "$mode"
        shift
        ;;
      # Set CPU pinning by allowing host use only specific cores
      --preserve-cores=*)
        cores="${i#*=}"
        preserve_cpu_cores "$cores"
        shift
        ;;
      # Enable live USB passthrough
      --usb-passthrough=*)
        device="${i#*=}"
        attach_usb_device "$device"
        shift
        ;;
      # Unknown or ignored
      *)
        ;;
    esac
  done

}

# On release end qemu hook
function on_release_end {

  for i in "$@"; do
    case $i in
      # Disable live GPU passthrough
      --gpu-passthrough=*)
        info=($(echo "${i#*=}" | tr ',' ' '))
        restore_gpu "${info[@]}"
        shift
        ;;
      # Restore CPU scaling governor
      --cpu-scaling-mode=*)
        restore_cpu_scaling_governor
        shift
        ;;
      # Restore CPU core pinning on system
      --preserve-cores=*)
        cores="${i#*=}"
        restore_cpu_cores "$cores"
        shift
        ;;
      # Unknown or ignored
      *)
        ;;
    esac
  done

  # Config clean up
  debug "Cleaning config cache"
  rm -f "${VMF}"-*

}

##################################
### ======== Execution ======= ###
##################################

debug "Hook called: ${OPERATION} ${ACTION}"

if [ -n "$(command -v "on_${OPERATION}_${ACTION}")" ]; then
  debug "Hook options: ${OPTIONS}"
  eval "on_${OPERATION}_${ACTION}" "${OPTIONS}"
fi
