# -*- coding: utf-8 -*-
import os, uuid
from datetime import datetime
from flask_app import logger

# from flask import current_app
# current_app.root_path
# DATABASE = 'mysql+pymysql://admin:password@192.168.168.212/kvm?charset=utf8mb4'
OUTDIR = os.environ.get('OUTDIR', os.path.abspath(os.path.dirname(__file__)))
DATABASE = os.environ.get('DATABASE', f'sqlite:///{OUTDIR}/kvm.db')

# import multiprocessing
# class Config:
#     shared_state_lock = multiprocessing.Lock()
#     shared_state = multiprocessing.Manager().dict()
#     # _shared_state.update({'k':'v'})
#     # _shared_state.clear()
#     def __init__(self, **kwargs):
#         for k, v in kwargs.items():
#             self.set(k, v)
#
#     def __getattr__(self, name):
#         if name in Config.shared_state:
#             return Config.shared_state[name]
#         raise AttributeError(f"'Config' object has no attribute '{name}'")
#
#     def set(self, name, value):
#          with Config.shared_state_lock:
#             Config.shared_state[name] = value
# config = Config(app_name="MyApp", version="1.0.0")
# print(config.app_name)  # Output: MyApp
# config.set("version", "2.0.0")
# print(config.version)  # Output: MyApp

class config:
    # # iso meta service dir & iso cd device dir
    ISO_DIR = os.path.join(OUTDIR, 'iso')
    # # gold disk dir
    GOLD_DIR = os.path.join(OUTDIR, 'gold')
    # # device action script dir
    ACTION_DIR = os.path.join(OUTDIR, 'actions')
    # # device template dir
    DEVICE_DIR = os.path.join(OUTDIR, 'devices')
    # # domain template dir
    DOMAIN_DIR = os.path.join(OUTDIR, 'domains')
    # # cloud-init meta template dir
    META_DIR = os.path.join(OUTDIR, 'meta')
    # # vnc/spice access token dir
    TOKEN_DIR = os.path.join(OUTDIR, 'token')
    # # NOCLOUD meta service data dir
    NOCLOUD_DIR = os.path.join(OUTDIR, 'nocloud')
    # # network pools,default gateway/network_address/broadcast_address in USED_ADDRESS 
    NETWORKS = [
                {'network':'192.168.168.0/24', 'gateway':'192.168.168.1'},
               ]
    USED_CIDR = ['192.168.168.2/24','192.168.168.3/24','192.168.168.4/24','192.168.168.5/24',]
    # # socat process close 10m
    SOCAT_TMOUT = '10m'
    VNC_DISP_URL = 'https://vmm.registry.local/novnc/vnc_lite.html'
    SPICE_DISP_URL = 'https://vmm.registry.local/spice/spice_auto.html'
    WEBSOCKIFY_SECURE_LINK_MYKEY = 'P@ssw@rd4Display'  # vnc/spice websockify access mykey
    WEBSOCKIFY_SECURE_LINK_EXPIRE = 24 * 60            # minutes
    USER_ACCESS_URL = 'https://vmm.registry.local/guest.html'
    USER_ACCESS_SECURE_LINK_MYKEY = 'P@ssw@rd4Display' # user.html access mykey, use use this page access vm by uuid belone him

    # # main:attach_device
    ATTACH_DEFAULT = {'size':'10','gold':''}
    META_DEFAULT = {'rootpass':'pass123','hostname':'vmsrv'}
    @staticmethod
    def VM_DEFAULT(arch, hostname):
        # TODO: VM_DEFAULT, can defined by hostname!
        # enum=OPENSTACK/EC2/NOCLOUD/None(undefine)
        #    EC2: uuid must startwith ec2........
        #    NOCLOUD: access http://169.254.169.254/<vm_uuid>
        #    None(undefine), use ISOMeta
        # when enum=NOCLOUD, nocloud_srv: default=http://169.254.169.254
        # if vm_ram_mb_max/vm_vcpus_max no set then use vm_ram_mb/vm_vcpus, else use a default value. see: domains/newvm.tpl...
        # # VM_DEFULT vars from domains/template. main:create_vm
        default = {'vm_arch':f'{arch.lower()}','vm_uuid':f'{uuid.uuid4()}','vm_name':'srv','vm_desc':'','vm_ram_mb':1024,'vm_ram_mb_max':16384,'vm_vcpus':1,'vm_vcpus_max':8,'vm_uefi':'','create_tm':datetime.now(),'nocloud_srv':'http://kvm.registry.local'}
        if (arch.lower() == 'x86_64'):
            return { **default }
        elif (arch.lower() == 'aarch64'):
            #  x86_64:/usr/share/qemu/OVMF.fd
            # aarch64:/usr/share/qemu-efi-aarch64/QEMU_EFI.fd
            #         /usr/share/AAVMF/AAVMF_CODE.fd
            #         # openEuler 22.03
            #         /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw
            return { **default, 'vm_uefi':'/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw' }
        else:
            logger.error(f'{arch} {hostname} no VM_DEFAULT defined')
            return {}
logger.info(f'OUTDIR={OUTDIR}')
