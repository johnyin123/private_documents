#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import print_function

from pyspark.sql import Row

# ======================
# log_format parsing
# ======================
import re

LOG_FORMAT = '"$time_iso8601" $scheme $http_host [$request_time|$upstream_response_time] $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" "$http_x_forwarded_for" $gzip_ratio'
REGEX_SPECIAL_CHARS = r'([\.\*\+\?\|\(\)\{\}\[\]])'
REGEX_LOG_FORMAT_VARIABLE = r'\$([a-zA-Z0-9\_]+)'

ptn = re.sub(REGEX_SPECIAL_CHARS, r'\\\1', LOG_FORMAT)
ptn = re.sub(REGEX_LOG_FORMAT_VARIABLE, '(?P<\\1>.*)', ptn)
pattern = re.compile(ptn)

# ======================
# Access log parsing
# ======================
try:
    import urlparse
except ImportError:
    import urllib.parse as urlparse

def parse_request_path(record):
    if 'request_uri' in record:
        uri = record['request_uri']
    elif 'request' in record:
        uri = ' '.join(record['request'].split(' ')[1:-1])
    else:
        uri = None
    return urlparse.urlparse(uri).path if uri else None

def to_int(value):
    return int(value) if value and value.isdigit() else 0

def to_float(value):
    try:
        return float(value) if value and value != '-' else 0.0
    except ValueError, e:
        return 0.0

import dateutil.parser
def iso8601_to_datetime(value):
    return dateutil.parser.parse(value) if value and value != '-' else dateutil.parser.parse("1970-01-01T00:00:00+00:00")

def parse_ngx_log_line(logline):
    match = pattern.match(logline)
    if match is None:
        raise Error("Invalid logline: %s" % logline)
    record = match.groupdict()
    record['status']                 = to_int(record.get('status', None))
    record['body_bytes_sent']        = to_int(record.get('body_bytes_sent', None))
    record['request_time']           = to_float(record.get('request_time', None))
    record['gzip_ratio']             = to_float(record.get('gzip_ratio', None))
    record['upstream_response_time'] = to_float(record.get('upstream_response_time', None))
    record['time_iso8601']           = iso8601_to_datetime(record.get('time_iso8601', None))
    record['request_path'] = parse_request_path(record)
    return Row(**record)
    #return Row(
    #    ip_address    = record.group(1),
    #    response_code = int(record.group(8)),
    #    content_size  = long(record.group(9))
    #)
