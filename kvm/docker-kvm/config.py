# -*- coding: utf-8 -*-
import os, uuid
from datetime import datetime

# from flask import current_app
# current_app.root_path
# DATABASE = 'mysql+pymysql://admin:password@192.168.168.212/kvm?charset=utf8mb4'
OUTDIR = os.environ.get('OUTDIR', os.path.abspath(os.path.dirname(__file__)))
DATABASE = os.environ.get('DATABASE', f'sqlite:///{OUTDIR}/kvm.db')
class Config:
    ISO_DIR = os.path.join(OUTDIR, 'iso')
    GOLD_DIR = os.path.join(OUTDIR, 'disk')
    ACTION_DIR = os.path.join(OUTDIR, 'actions')
    DEVICE_DIR = os.path.join(OUTDIR, 'devices')
    DOMAIN_DIR = os.path.join(OUTDIR, 'domains')
    META_DIR = os.path.join(OUTDIR, 'meta')
    TOKEN_DIR = os.path.join(OUTDIR, 'token')
    # # socat process close 10m
    SOCAT_TMOUT = '10m'
    VNC_DISP_URL = 'https://vmm.registry.local/novnc/vnc_lite.html'
    SPICE_DISP_URL = 'https://vmm.registry.local/spice/spice_auto.html'
    # # main:attach_device
    ATTACH_DEFAULT = {'size':'10G','gold':''}
    @property
    def VM_DEFAULT(self):
        # # VM_DEFULT vars from domains/template. main:create_vm
        #'vm_uefi':'/usr/share/qemu/OVMF.fd' ,default bios mode
        return {'vm_arch':'x86_64','vm_uuid':f'{uuid.uuid4()}','vm_name':'srv','vm_desc':'','vm_ram_mb':1024,'vm_ram_mb_max':16384,'vm_vcpus':1,'vm_vcpus_max':8,'vm_uefi':'','create_tm':f'{datetime.now().strftime("%Y%m%d%H%M%S")}'}

config = Config()
