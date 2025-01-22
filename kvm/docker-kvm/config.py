# -*- coding: utf-8 -*-
import os
DATABASE = 'sqlite:///./kvm.db'
CONF_DIR = os.path.abspath(os.path.dirname(__file__))
OUTDIR = os.environ.get('OUTDIR', os.path.join(CONF_DIR, '.')))
GOLD_DIR = os.path.join(CONF_DIR, 'disk')
ACTION_DIR = os.path.join(CONF_DIR, 'actions')
DEVICE_DIR = os.path.join(CONF_DIR, 'devices')
DOMAIN_DIR = os.path.join(CONF_DIR, 'domains')
META_DIR = os.path.join(CONF_DIR, 'meta')
