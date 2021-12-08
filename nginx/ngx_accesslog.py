#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import print_function
import logging, sys, os

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
    except ValueError:
        return 0.0

import dateutil.parser
def iso8601_to_datetime(value):
    return dateutil.parser.parse(value) if value and value != '-' else dateutil.parser.parse("1970-01-01T00:00:00+00:00")

def parse_log(lines, pattern):
    matches = (pattern.match(l) for l in lines)
    records = (m.groupdict() for m in matches if m is not None)
    records = map_field('status', to_int, records)
    records = map_field('request_length', to_int, records)
    records = map_field('bytes_sent', to_int, records)
    records = map_field('request_time', to_float, records)
    records = map_field('gzip_ratio', to_float, records)
    # 0.881, 1.463, 0.454
    # records = map_field('upstream_response_time', to_float, records)
    records = map_field('time_iso8601', iso8601_to_datetime, records)
    records = add_field('request_path', parse_request_path, records)
    return records

def main():
    args = {
            "log-format": '$scheme $http_host $server_port "$upstream_addr" [$request_time|"$upstream_response_time"|"$upstream_status"] $remote_addr - $remote_user [$time_local] "$request" $status $request_length $bytes_sent "$http_referer" "$http_user_agent" "$http_x_forwarded_for" $gzip_ratio',
            "debug":False
           }
    log_level = logging.WARNING
    if args["debug"]:
        log_level = logging.DEBUG
    logging.basicConfig(level=log_level, format="%(levelname)s: %(message)s")
    logging.debug("arguments:\n%s", args)
    if sys.stdin.isatty():
        logging.error("no input")
        sys.exit(1)
    access_log = sys.stdin
    pattern = build_pattern(args["log-format"])
    try:
        records = parse_log(access_log, pattern)
        for r in records:
            print(r["http_host"])
            print(r["upstream_addr"])
            print(r["bytes_sent"])
            print(r["request_length"])
            print(r["upstream_response_time"])
    except KeyboardInterrupt:
        logging.info("interrupt signal received")
        sys.exit(0)

if __name__ == '__main__':
    main()
