#!/bin/bash
set -u -o pipefail

readonly BASEDIR="$(readlink -f "$(dirname "$0")")"
BP_DIR=${BP_DIR:-${BASEDIR}/blueprints}
BP_NAME=${BP_NAME:-"DEMO"}
BP_NAME=${BP_NAME//-/_}
function uppercase() {
    echo "${*^^}"
}

function lowercase() {
    echo "${*,,}"
}
BP_NAME=$(lowercase $BP_NAME)

function gen_dirtree() {
    local bp_dir=$1
    local bp_name=$2
    mkdir -p ${bp_dir}/${bp_name} ${bp_dir}/templates/${bp_name} ${bp_dir}/static/${bp_name}
    return $?
}

function gen_initpy() {
    local bp_dir=$1
    local bp_name=$2
    cat >${bp_dir}/${bp_name}/__init__.py <<EOF
# -*- coding: utf-8 -*-

from __future__ import print_function
from flask import Blueprint

module = Blueprint("${bp_name}", __name__)

from . import views
EOF
}

function gen_viewpy() {
    local bp_dir=$1
    local bp_name=$2
    cat >${bp_dir}/${bp_name}/views.py <<EOF
# -*- coding: utf-8 -*-

from __future__ import print_function
from flask import current_app, render_template, abort, request, flash, redirect, url_for, json, make_response
from flask_login import current_user, login_required
from . import module

@module.route("/")
def index():
    current_app.logger.debug('A value for debugging')
    current_app.logger.error('An error occurred')
    resp = make_response(render_template("/${bp_name}/index.html"))
    resp.headers['Content-type'] = "text/xml; charset=utf-8"
    return resp
EOF
}
function gen_html() {
    local bp_dir=$1
    local bp_name=$2
    cat >${bp_dir}/templates/${bp_name}/index.html<<EOF
{#- 多个Templates目录时候，flask合并处理，
    有相同子目录和名字的文件，会取第一个注册的bluepoint
#}
{%- extends "/base.html" %}
{%- block custom_head_tags %}{%- endblock %}
{%- block page_title %}${bp_name}-index page{%- endblock %}
{%- block content %}
    {#- It's a security feature, use it on all untrusted variables #}
    <h1>Hello, {{ name | e }}</h1>
    {#- url_for("static", filename="${bp_name}/style.css") ==> app/static/${bp_name}/style.css#}
    {%- if current_user.is_authenticated %}
    <li>
      <a href="#">{{current_user.name}}</a>
    </li>
    <li>
      <a href="{{ url_for("flask_login.logout") }}">Logout</a>
    </li>
    {%- else %}
    <li><a href="{{ url_for("flask_login.login") }}">Login</a></li>
    {%- endif %}
    <h1 class="ui header">${bp_name}</h1>
        <h3 class="ui header">index.app</h3>
{%- endblock %}
{%- block tail_script %}{%- endblock %}
EOF
}

gen_dirtree ${BP_DIR} ${BP_NAME}
retval=$?
if [[ $retval != 0  ]]; then
    echo "error create dir ${BP_DIR} ${BP_NAME}"
    exit 1
fi
gen_initpy ${BP_DIR} ${BP_NAME}
gen_viewpy ${BP_DIR} ${BP_NAME}
gen_html ${BP_DIR} ${BP_NAME}

