# -*- coding: utf-8 -*-

from __future__ import print_function
from flask import Blueprint

module = Blueprint("flask_login", __name__)

from . import views
