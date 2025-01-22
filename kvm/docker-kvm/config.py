# -*- coding: utf-8 -*-
import os
DATABASE = 'sqlite:///kvm.db'
# DATABASE = 'mysql+pymysql://admin:password@192.168.168.212/kvm?charset=utf8mb4'
CONF_DIR = os.path.abspath(os.path.dirname(__file__))
OUTDIR = os.environ.get('OUTDIR', os.path.join(CONF_DIR, '.'))
GOLD_DIR = os.path.join(CONF_DIR, 'disk')
ACTION_DIR = os.path.join(CONF_DIR, 'actions')
DEVICE_DIR = os.path.join(CONF_DIR, 'devices')
DOMAIN_DIR = os.path.join(CONF_DIR, 'domains')
META_DIR = os.path.join(CONF_DIR, 'meta')
