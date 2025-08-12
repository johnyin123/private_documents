# -*- coding: utf-8 -*-
import os, uuid
from datetime import datetime
# # env: OUTDIR, DATABASE, META_SRV, CTRL_PANEL_SRV, CTRL_PANEL_KEY
OUTDIR           = os.environ.get('OUTDIR', os.path.abspath(os.path.dirname(__file__)))
DATABASE         = os.environ.get('DATABASE', f'sqlite:///{OUTDIR}/kvm.db?check_same_thread=False')
# # clout-init: nocloud http://META_SRV, iso https://META_SRV as meta server.
META_SRV         = os.environ.get('META_SRV', 'vmm.registry.local')
# # http srv for user control panel srv, default https://{META_SRV}
CTRL_PANEL_SRV   = os.environ.get('CTRL_PANEL_SRV', META_SRV)
CTRL_PANEL_KEY   = os.environ.get('CTRL_PANEL_KEY', 'P@ssw@rd4Display')  # user control panel access mykey
##################################################################
# # const define
TMOUT_MINS_SOCAT = f'15' # socat process timeout close minutes, default value
CDROM_TPL        = f'cdrom.meta.tpl'               # change media use this as template
URI_VNC          = f'/novnc/vnc_lite.html'
URI_SPICE        = f'/spice/spice_auto.html'
URI_CONSOLE      = f'/term/xterm.html'
URI_CTRL_PANEL   = f'https://{CTRL_PANEL_SRV}/guest.html'
DIR_CIDATA       = os.path.join(OUTDIR, 'cidata')  # RW # iso-meta/nocloud-meta data dir
DIR_ACTION       = os.path.join(OUTDIR, 'actions') # RO # device action script dir
DIR_DEVICE       = os.path.join(OUTDIR, 'devices') # RO # device template dir
DIR_DOMAIN       = os.path.join(OUTDIR, 'domains') # RO # domain template dir
DIR_META         = os.path.join(OUTDIR, 'meta')    # RO # cloud-init template dir
DIR_TOKEN        = os.path.join(OUTDIR, 'token')   # RW # vnc/spice access token dir
DIR_REQ_JSON     = os.path.join(OUTDIR, 'reqlogs') # RW # LOG create_vm req_json
# # vm define default values
def VM_DEFAULT(arch:str, hostname:str):
    arch = arch.lower()
    default = {
        'vm_ram_mb': 1024, 'vm_vcpus': 1,
        'vm_arch': arch, 'vm_uuid': f'{uuid.uuid4()}', 'vm_create': datetime.now().isoformat()
    }
    # datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    if (arch == 'x86_64'):
        return { **default };
    elif (arch == 'aarch64'):
        return { **default, 'vm_uefi':'/usr/share/AAVMF/AAVMF_CODE.fd' }
    raise Exception(f'{arch} {hostname} no VM_DEFAULT defined')
