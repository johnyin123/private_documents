# -*- coding: utf-8 -*-
import os, uuid
from typing import Dict
from datetime import datetime

# DATABASE = 'mysql+pymysql://admin:password@192.168.168.212/kvm?charset=utf8mb4'
# # mgr/meta-data http/https server name
META_SRV = os.environ.get('META_SRV', 'vmm.registry.local')
OUTDIR = os.environ.get('OUTDIR', os.path.abspath(os.path.dirname(__file__)))
DATABASE = os.environ.get('DATABASE', f'sqlite:///{OUTDIR}/kvm.db?check_same_thread=False')

SOCAT_TMOUT = '10m' # # socat process close 10m
WEBSOCKIFY_SECURE_LINK_MYKEY = 'P@ssw@rd4Display'  # vnc/spice websockify access mykey
WEBSOCKIFY_SECURE_LINK_EXPIRE = 24 * 60            # minutes
USER_ACCESS_SECURE_LINK_MYKEY = 'P@ssw@rd4Display' # user.html access mykey, use use this page access vm by uuid belone him
NETWORKS = [{'network':'192.168.168.0/24', 'gateway':'192.168.168.1'},]
USED_CIDR = ['192.168.168.2/24','192.168.168.3/24','192.168.168.4/24','192.168.168.5/24',]
# # const define
VNC_DISP_URL = f'https://{META_SRV}/novnc/vnc_lite.html'
SPICE_DISP_URL = f'https://{META_SRV}/spice/spice_auto.html'
CONSOLE_URL = f'https://{META_SRV}/term/xterm.html'
USER_ACCESS_URL = f'https://{META_SRV}/guest.html'
CDROM_TPL = 'cdrom-meta.tpl'           # change media use this as template
ISO_DIR = os.path.join(OUTDIR, 'iso')  # # iso-meta/nocloud-meta data dir
GOLD_DIR = os.path.join(OUTDIR, 'gold') # # gold disk dir
ACTION_DIR = os.path.join(OUTDIR, 'actions') # # device action script dir
DEVICE_DIR = os.path.join(OUTDIR, 'devices') # # device template dir
DOMAIN_DIR = os.path.join(OUTDIR, 'domains') # # domain template dir
META_DIR = os.path.join(OUTDIR, 'meta') # # cloud-init meta template dir
TOKEN_DIR = os.path.join(OUTDIR, 'token') # # vnc/spice access token dir
REQ_JSON_DIR = os.path.join(OUTDIR, 'request') # # create_vm request json logs

# # vm define default values
def VM_DEFAULT(arch:str='x86_64', hostname:str='dummy')->Dict:
    # TODO: VM_DEFAULT, can defined by hostname!
    # if vm_ram_mb_max/vm_vcpus_max no set then use vm_ram_mb/vm_vcpus, else use a default value. see: domains/newvm.tpl...
    # # VM_DEFULT vars from domains/template. main:create_vm
    arch = arch.lower()
    default = {
        'vm_arch': arch,
        'vm_uuid': f'{uuid.uuid4()}',
        'vm_name': 'srv',
        'vm_desc': '',
        'vm_ram_mb': 1024,
        'vm_ram_mb_max': 16384,
        'vm_vcpus': 1,
        'vm_vcpus_max': 8,
        'vm_uefi': '',
        'create_tm': datetime.now().isoformat(),
        'META_SRV': META_SRV
    }
    if (arch == 'x86_64'):
        return { **default }
    elif (arch == 'aarch64'):
        #  x86_64:/usr/share/qemu/OVMF.fd
        # aarch64:/usr/share/qemu-efi-aarch64/QEMU_EFI.fd
        #         /usr/share/AAVMF/AAVMF_CODE.fd
        #         # openEuler 22.03, use docker-libvirt NOT
        #         /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw
        return { **default, 'vm_uefi':'/usr/share/AAVMF/AAVMF_CODE.fd' }
    else:
        return {'error':f'{arch} {hostname} no VM_DEFAULT defined'}

# OUTDIR=/abc python3 -c 'import config; print(config.ISO_DIR)'
