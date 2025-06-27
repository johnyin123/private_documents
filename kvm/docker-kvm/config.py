# -*- coding: utf-8 -*-
import os, uuid
from datetime import datetime

# DATABASE = 'mysql+pymysql://admin:password@192.168.168.212/kvm?charset=utf8mb4'
OUTDIR = os.environ.get('OUTDIR', os.path.abspath(os.path.dirname(__file__)))
DATABASE = os.environ.get('DATABASE', f'sqlite:///{OUTDIR}/kvm.db?check_same_thread=False')
# # template vars desc json file contents
VARS_DESC = {}
# # cloud-init meta-data http/https server name
META_SRV = os.environ.get('META_SRV', 'vmm.registry.local')

TMOUT_MINS_SOCAT = '15' # # socat process close 15 minutes
SECURE_LINK_MYKEY_WEBSOCKIFY = 'P@ssw@rd4Display'  # vnc/spice websockify access mykey
SECURE_LINK_MYKEY_CTRL_PANEL = 'P@ssw@rd4Display' # user.html access mykey, use use this page access vm by uuid belone him
# # const define
CDROM_TPL = 'cdrom.meta.tpl'           # change media use this as template
URI_VNC        = f'/novnc/vnc_lite.html'
URI_SPICE      = f'/spice/spice_auto.html'
URI_CONSOLE    = f'/term/xterm.html'
URI_CTRL_PANEL = f'/guest.html'
DIR_CIDATA   = os.path.join(OUTDIR, 'cidata')  # RW # iso-meta/nocloud-meta data dir
DIR_ACTION   = os.path.join(OUTDIR, 'actions') # RO # device action script dir
DIR_DEVICE   = os.path.join(OUTDIR, 'devices') # RO # device template dir
DIR_DOMAIN   = os.path.join(OUTDIR, 'domains') # RO # domain template dir
DIR_META     = os.path.join(OUTDIR, 'meta')    # RO # cloud-init template dir
DIR_TOKEN    = os.path.join(OUTDIR, 'token')   # RW # vnc/spice access token dir
DIR_REQ_JSON = os.path.join(OUTDIR, 'reqlogs') # RW # LOG create_vm req_json
# # vm define default values
def VM_DEFAULT(arch:str, hostname:str):
    arch = arch.lower()
    default = {
        'vm_ram_mb': 1024, 'vm_vcpus': 1,
        'vm_arch': arch, 'vm_uuid': f'{uuid.uuid4()}', 'vm_create': datetime.now().isoformat()
    }
    if (arch == 'x86_64'):
        return { **default };
    elif (arch == 'aarch64'):
        return { **default, 'vm_uefi':'/usr/share/AAVMF/AAVMF_CODE.fd' }
    raise Exception(f'{arch} {hostname} no VM_DEFAULT defined')
