# -*- coding: utf-8 -*-
import os, uuid
from datetime import datetime
import flask_app
logger=flask_app.logger

# from flask import current_app
# current_app.root_path
# DATABASE = 'mysql+pymysql://admin:password@192.168.168.212/kvm?charset=utf8mb4'
OUTDIR = os.environ.get('OUTDIR', os.path.abspath(os.path.dirname(__file__)))
DATABASE = os.environ.get('DATABASE', f'sqlite:///{OUTDIR}/kvm.db')

# class Singleton(type):
#     _instances = {}
#     def __call__(cls, *args, **kwargs):
#         if cls not in cls._instances:
#             cls._instances[cls] = super(Singleton, cls).__call__(*args, **kwargs)
#         return cls._instances[cls]
# class Config(metaclass=Singleton):
#     def __init__(self, **kwargs):
#         self._config = kwargs
#         logger.info(f'config __init__ {kwargs}')
#     def __getattr__(self, name):
#         if name in self._config:
#             return self._config[name]
#         raise AttributeError(f"'Config' object has no attribute '{name}'")
#     def set(self, name, value):
#          self._config[name] = value
# config = Config(app_name="MyApp", version="1.0.0")
# print(config.app_name)  # Output: MyApp
# config.set("version", "2.0.0")
# print(config.version) # Output: 2.0.0

class config:
    ISO_DIR = os.path.join(OUTDIR, 'iso')
    GOLD_DIR = os.path.join(OUTDIR, 'disk')
    ACTION_DIR = os.path.join(OUTDIR, 'actions')
    DEVICE_DIR = os.path.join(OUTDIR, 'devices')
    DOMAIN_DIR = os.path.join(OUTDIR, 'domains')
    META_DIR = os.path.join(OUTDIR, 'meta')
    TOKEN_DIR = os.path.join(OUTDIR, 'token')
    # # NOCLOUD meta service data dir
    NOCLOUD_DIR = os.path.join(OUTDIR, 'nocloud')
    # # network pools
    NETWORKS = [
                {'network':'192.168.167.0/24', 'gateway':'192.168.167.1'},
                {'network':'192.168.168.0/24', 'gateway':'192.168.168.1'},
               ]
    # # socat process close 10m
    SOCAT_TMOUT = '10m'
    VNC_DISP_URL = 'https://vmm.registry.local/novnc/vnc_lite.html'
    SPICE_DISP_URL = 'https://vmm.registry.local/spice/spice_auto.html'
    # # main:attach_device
    ATTACH_DEFAULT = {'size':'10','gold':''}
    META_DEFAULT = {'rootpass':'pass123','hostname':'vmsrv'}
    @staticmethod
    def VM_DEFAULT(arch, hostname):
        # TODO: VM_DEFAULT, can defined by hostname!
        # enum=OPENSTACK/EC2/NOCLOUD/None(undefine)
        #    EC2: uuid must startwith ec2........
        #    NOCLOUD: access http://169.254.169.254/<vm_uuid>
        # nocloud_srv=http://169.254.169.254 or http://dnsname
        # if vm_ram_mb_max/vm_vcpus_max no set then use vm_ram_mb/vm_vcpus, else use a default value. see: domains/newvm.tpl...
        # # VM_DEFULT vars from domains/template. main:create_vm
        default = {'vm_arch':f'{arch.lower()}','vm_uuid':f'{uuid.uuid4()}','vm_name':'srv','vm_desc':'','vm_ram_mb':1024,'vm_ram_mb_max':16384,'vm_vcpus':1,'vm_vcpus_max':8,'vm_uefi':'','create_tm':f'{datetime.now().strftime("%Y%m%d%H%M%S")}'}
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
