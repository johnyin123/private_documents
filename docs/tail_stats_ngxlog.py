#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import print_function

import sys, os
import json

access_stats = {}

# ======================
# log_format parsing
# ======================
import re

REGEX_SPECIAL_CHARS = r'([\.\*\+\?\|\(\)\{\}\[\]])'
REGEX_LOG_FORMAT_VARIABLE = r'\$([a-zA-Z0-9\_]+)'

def build_pattern(log_format):
    """
    Build regular expression to parse given format.
    :param log_format: format string to parse
    :return: regular expression to parse given format
    """
    pattern = re.sub(REGEX_SPECIAL_CHARS, r'\\\1', log_format)
    pattern = re.sub(REGEX_LOG_FORMAT_VARIABLE, '(?P<\\1>.*)', pattern)
    return re.compile(pattern)

def extract_variables(log_format):
    """
    Extract all variables from a log format string.
    :param log_format: format string to extract
    :return: iterator over all variables in given format string
    """
    for match in re.findall(REGEX_LOG_FORMAT_VARIABLE, log_format):
        yield match

# =================================
# Simple Records processor
# =================================
import pathlib

class SimpleProcessor(object):
    def __init__(self, fields):
        self.fields = fields if fields is not None else []
        #print(fields)
        pass

    def process(self, records):
        for r in records:
            try:
                up_status = r['upstream_status']
                status = r['status']
                if up_status.startswith('2') or up_status.startswith('3') or status.startswith('2') or status.startswith('3'):
                    continue
                parts = pathlib.PurePosixPath(r['request_path']).parts
                path = (parts[0] if len(parts)>0 else '/') + (parts[1] if len(parts)>1 else '')

                host = r['http_host']
                if host in access_stats.keys():
                    if path in access_stats[host].keys():
                       if up_status in access_stats[host][path].keys():
                           access_stats[host][path][up_status] += 1
                       else:
                           access_stats[host][path][up_status] = 1
                    else:
                       access_stats[host][path] = { up_status : 1}
                else:
                    access_stats[host] = { path : { up_status : 1} }
            except TypeError, e:
                print(r)
                pass

def map_field(field, func, dict_sequence):
    """
    Apply given function to value of given key in every dictionary in sequence and
    set the result as new value for that key.
    """
    for item in dict_sequence:
        try:
            item[field] = func(item.get(field, None))
            yield item
        except ValueError:
            pass

def add_field(field, func, dict_sequence):
    """
    Apply given function to the record and store result in given field of current record.
    Do nothing if record already contains given field.
    """
    for item in dict_sequence:
        if field not in item:
            item[field] = func(item)
        yield item


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
    return urlparse.urlparse(uri).path if uri else ''

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

def parse_log(lines, pattern):
    matches = (pattern.match(l) for l in lines)
    records = (m.groupdict() for m in matches if m is not None)
    #records = map_field('status', to_int, records)
    records = map_field('body_bytes_sent', to_int, records)
    records = map_field('request_time', to_float, records)
    records = map_field('gzip_ratio', to_float, records)
    records = map_field('upstream_response_time', to_float, records)
    records = add_field('request_path', parse_request_path, records)
    return records

# ===============
# Log processing
# ===============

def process_log(lines, pattern, processor, arguments):
    records = parse_log(lines, pattern)
    processor.process(records)

def process(arguments):
    log_format = arguments["log-format"]
    pattern = build_pattern(log_format)
    fields = [r for r in extract_variables(log_format)]
    fields.append("request_path")
    processor = SimpleProcessor(fields)
    process_log(arguments["access_log"], pattern, processor, arguments)

import collections
def tail(iterable, N):
    deq = collections.deque()
    for thing in iterable:
        if len(deq) >= N:
            deq.popleft()
        deq.append(thing)
    for thing in deq:
        yield thing

def main():
    args = {
        "log-format": '$scheme $http_host [$request_time|$upstream_response_time|$upstream_status] $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" "$http_x_forwarded_for" $gzip_ratio',
        "access_log": None,
        }
    try:
        fn = "access.log"
        #if os.path.isfile(fn):
        #    fp = open(fn, 'r')
        #    args["access_log"] = fp #tail(fp, 50000)
        if sys.stdin.isatty():
            sys.stderr.write('Error: need access.log stream')
            sys.exit(1)
        args["access_log"] = sys.stdin

        process(args)
        #fp.close()

        print(json.dumps(access_stats, indent=4, ensure_ascii=False))
    except KeyboardInterrupt:
        print("interrupt signal received")
        sys.exit(0)

if __name__ == '__main__':
    main()
