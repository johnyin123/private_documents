# -*- coding: utf-8 -*-
import os
# DATABASE = 'mysql+pymysql://admin:password@192.168.168.212/kvm?charset=utf8mb4'
class config:
    DATABASE = os.environ.get('DATABASE', 'sqlite:///kvm.db')
    OUTDIR = os.environ.get('OUTDIR', os.path.abspath(os.path.dirname(__file__)))
    GOLD_DIR = os.path.join(OUTDIR, 'disk')
    ACTION_DIR = os.path.join(OUTDIR, 'actions')
    DEVICE_DIR = os.path.join(OUTDIR, 'devices')
    DOMAIN_DIR = os.path.join(OUTDIR, 'domains')
    META_DIR = os.path.join(OUTDIR, 'meta')
    TOKEN_DIR = os.path.join(OUTDIR, 'token')
    DISP_URL = 'https://vmm.registry.local/novnc/vnc_lite.html'
#https://vmm.registry.local/novnc/vnc_lite.html?password={passwd}&path=websockify/?token={uuid}
