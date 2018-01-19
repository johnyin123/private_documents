# -*- coding: utf-8 -*-

from __future__ import print_function
from flask import Blueprint

module = Blueprint("index", __name__)

from . import views
