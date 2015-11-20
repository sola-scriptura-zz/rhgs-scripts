#!/usr/bin/python

# size_histogram.py -- compute size histogram with power-of-2 buckets for all file sizes in input file
# example of how to generate inputs for this program:
#   find -type f -printf "%s\n" | sort -n | python size_histogram.py

import os
import sys
import math

buckets = {}
max_bucket = -1
zero_length_files = 0
for sz_str in sys.stdin.readlines():
  stripped = sz_str.strip()
  if stripped == '': 
    continue # skip
  sz = int(stripped)
  if sz == 0:
    zero_length_files += 1 # prevent math domain error
  else:
    log2 = + int(math.log(sz, 2.0))
    #print '%d, %d'%(sz, log2)
    if log2 > max_bucket: max_bucket = log2
    try:
      buckets[log2] += 1
    except KeyError as e:
      buckets[log2] = 1


print 'zero-length files = %d'%zero_length_files
print '[ range-min  , range-max ],   count'
for j in range(0, max_bucket):
  try:
    files_in_range = buckets[j]
  except KeyError as e:
    files_in_range = 0
  bucket_min_size = int(math.pow(2, j))
  bucket_max_size = int(math.pow(2, j+1)) - 1
  print '    %-12d %-12d %d'%(bucket_min_size, bucket_max_size, files_in_range)
print buckets
