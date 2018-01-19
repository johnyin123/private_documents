# -*- coding: utf-8 -*-

from __future__ import print_function
from flask import Blueprint

module = Blueprint("static_page", __name__)


import os
from flask import send_from_directory
from flask_login import login_required

@module.route('/protected/<path:filename>')
@login_required
def protected(filename):
    return send_from_directory(os.path.join(module.root_path, 'protected'), filename)
