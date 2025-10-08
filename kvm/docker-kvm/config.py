# -*- coding: utf-8 -*-
import os, uuid, datetime
# # env: DATA_DIR, TOKEN_DIR, META_SRV, GOLD_SRV, CTRL_PANEL_SRV, CTRL_PANEL_KEY
DATA_DIR         = os.environ.get('DATA_DIR', os.path.abspath(os.path.dirname(__file__)))
# use etcd as persistent
ETCD_PREFIX      = os.environ.get('ETCD_PREFIX', None)
ETCD_SRV         = os.environ.get('ETCD_SRV', 'localhost')
ETCD_PORT        = os.environ.get('ETCD_PORT', 2379)
ETCD_CA          = os.environ.get('ETCD_CA', None)
ETCD_KEY         = os.environ.get('ETCD_KEY', None)
ETCD_CERT        = os.environ.get('ETCD_CERT', None)
# share with websockify process.
TOKEN_DIR        = os.environ.get('TOKEN_DIR', os.path.join(DATA_DIR, 'token'))
# # clout-init: net http://META_SRV/(uuid)/(meta-data|user-data) (domain.tpl)
# # clout-init: iso http://META_SRV/(uuid)/cidata.iso
# # iso.json  :     http://META_SRV/uri                          (same as clout-init iso)
# # META_SRV: Only for *KVMHOST* use. meta-data/user-data/cidata.iso and iso.json
META_SRV         = os.environ.get('META_SRV', 'vmm.registry.local')
# # GOLD_SRV: Only for *APP ACTIONS* use. http://GOLD_SRV/uri, golds.json
GOLD_SRV         = os.environ.get('GOLD_SRV', META_SRV)
# # CTRL_PANEL_SRV: https srv for user control panel, default https://META_SRV
CTRL_PANEL_SRV   = os.environ.get('CTRL_PANEL_SRV', META_SRV)
# # user control panel access mykey
CTRL_PANEL_KEY   = os.environ.get('CTRL_PANEL_KEY', 'P@ssw@rd4Display')
##################################################################
# # const define
TMOUT_MINS_SOCAT = f'15' # socat process timeout close minutes, default value
URI_VNC          = f'/novnc/vnc_lite.html'
URI_SPICE        = f'/spice/spice_auto.html'
URI_CONSOLE      = f'/term/xterm.html'
URL_CTRL_PANEL   = f'https://{CTRL_PANEL_SRV}/guest.html'
DIR_CIDATA       = os.path.join(DATA_DIR, 'cidata')  # RWS  # share iso-meta/nocloud-meta data dir
DIR_DEVICE       = os.path.join(DATA_DIR, 'devices') # ROL  # local device template dir
DIR_DOMAIN       = os.path.join(DATA_DIR, 'domains') # ROL  # local domain template dir
DIR_META         = os.path.join(DATA_DIR, 'meta')    # ROL  # local cloud-init template dir
FILE_HOSTS       = os.path.join(DATA_DIR, 'hosts.json')
FILE_DEVICES     = os.path.join(DATA_DIR, 'devices.json')
FILE_GOLDS       = os.path.join(DATA_DIR, 'golds.json')
FILE_ISO         = os.path.join(DATA_DIR, 'iso.json')
FILE_VARS        = os.path.join(DATA_DIR, 'vars.json')
# # # # # # # # # # # # # # # # # # # # # # #
# # vm define default values
def VM_DEFAULT(arch:str, hostname:str):
    arch = arch.lower()
    default = { 'vm_ram_mb': 1024, 'vm_vcpus': 1, 'vm_arch': arch, 'vm_uuid': str(uuid.uuid4()), 'vm_create': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S') }
    if (arch == 'aarch64'):
        default.update({'vm_uefi':'/usr/share/AAVMF/AAVMF_CODE.fd'})
    return default;
