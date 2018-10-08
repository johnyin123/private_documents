#!/usr/bin/env python
# -*- coding: utf-8 -*-

from __future__ import print_function

import logging, sys, os

# ======================
# regex parsing
# ======================
import re

REGEX_SPECIAL_CHARS = r'([\.\*\+\?\|\(\)\{\}\[\]])'
REGEX_LOG_FORMAT_VARIABLE = r'\$([a-zA-Z0-9\_]+)'

class RegexProcessor(object):
    def __init__(self, fmt, var_charset = REGEX_LOG_FORMAT_VARIABLE, special_chars = REGEX_SPECIAL_CHARS):
        """
        Build regular expression to parse given format.
        :param fmt: format string to parse
        """
        self.fmt = fmt
        ptn = re.sub(special_chars, r'\\\1', fmt)
        ptn = re.sub(var_charset, '(?P<\\1>.*)', ptn)
        self.pattern = re.compile(ptn)
        self.var_list = re.findall(var_charset, fmt)

    def extract_variables(self):
        return self.var_list
        #for match in re.findall(REGEX_LOG_FORMAT_VARIABLE, self.fmt):
        #    yield match

    def parse(self, line):
        """
        parse line with pattern.
        :param line: input string to extract
        :return: dict
        """
        matchs = self.pattern.match(line)
        return (matchs.groupdict() if matchs is not None else None)

import multiprocessing
from contextlib import contextmanager
from functools import partial
@contextmanager
def poolcontext(*args, **kwargs):
    pool = multiprocessing.Pool(*args, **kwargs)
    yield pool
    pool.terminate()

def worker(line, regex):
    ret = regex.parse(line)
    return ret 

def main():
    log_fmt = '"$time_iso8601" $scheme $http_host [$request_time|$upstream_response_time] $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent" "$http_x_forwarded_for" $gzip_ratio'
    regex = RegexProcessor(log_fmt)
    fields = regex.extract_variables()
    print(type(fields), fields)

    if sys.stdin.isatty():
        infile = open(sys.argv[1])
    else:
        infile = sys.stdin

    with poolcontext(multiprocessing.cpu_count()) as pool:
        results = pool.imap_unordered(partial(worker, regex=regex), infile)
        for i in results:
            print(i)
 
if __name__ == '__main__':
    main()
