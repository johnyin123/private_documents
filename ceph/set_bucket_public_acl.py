#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import boto3
import json

access_key = "7PAHUZN5L8TU7I3F5PKE"
secret_key = "aIXyBZprCOKDsXM3xdqMLAMHPed36LKldqGjFXU8"
s3_host = 'http://192.168.168.131'
bucket_name = "public-bucket"

conn = boto3.client('s3',
        aws_secret_access_key = secret_key,
        aws_access_key_id = access_key,
        endpoint_url = s3_host)

bucket_policy = {
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"AddPerm",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource":["arn:aws:s3:::{0}/*".format(bucket_name)]
    }
  ]
}

bucket_policy = json.dumps(bucket_policy)
conn.put_bucket_policy(Bucket=bucket_name, Policy=bucket_policy)
