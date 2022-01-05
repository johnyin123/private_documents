#!/usr/bin/env python3
# -*- coding: utf-8 -*- 
# python3 -m cProfile -o profiling_results <test.py>
import pstats
stats = pstats.Stats("profiling_results")
stats.sort_stats("tottime")
stats.print_stats(10)
