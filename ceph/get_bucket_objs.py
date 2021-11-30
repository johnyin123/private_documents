#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import boto3
import json

access_key = "7PAHUZN5L8TU7I3F5PKE"
secret_key = "aIXyBZprCOKDsXM3xdqMLAMHPed36LKldqGjFXU8"
s3_host = 'http://192.168.168.131'
bucket_name = "public-bucket"

#conn = boto3.client('s3',
#        aws_secret_access_key = secret_key,
#        aws_access_key_id = access_key,
#        endpoint_url = s3_host)
conn = boto3.resource('s3',
        aws_secret_access_key = secret_key,
        aws_access_key_id = access_key,
        endpoint_url = s3_host)
bucket = conn.Bucket('public-bucket')
for obj in bucket.objects.all():
    print(obj.key)
