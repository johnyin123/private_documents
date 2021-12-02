#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Operation                          Permission
# s3:GetObject                       READ
# s3:GetObjectTorrent                READ
# s3:GetObjectVersion                READ
# s3:GetObjectVersionTorrent         READ
# s3:GetObjectTagging                READ
# s3:GetObjectVersionTagging         READ
# s3:ListAllMyBuckets                READ
# s3:ListBucket                      READ
# s3:ListBucketMultipartUploads      READ
# s3:ListBucketVersions              READ
# s3:ListMultipartUploadParts        READ
# s3:AbortMultipartUpload            WRITE
# s3:CreateBucket                    WRITE
# s3:DeleteBucket                    WRITE
# s3:DeleteObject                    WRITE
# s3:s3DeleteObjectVersion           WRITE
# s3:PutObject                       WRITE
# s3:PutObjectTagging                WRITE
# s3:PutObjectVersionTagging         WRITE
# s3:DeleteObjectTagging             WRITE
# s3:DeleteObjectVersionTagging      WRITE
# s3:RestoreObject                   WRITE
# s3:GetAccelerateConfiguration      READ_ACP
# s3:GetBucketAcl                    READ_ACP
# s3:GetBucketCORS                   READ_ACP
# s3:GetBucketLocation               READ_ACP
# s3:GetBucketLogging                READ_ACP
# s3:GetBucketNotification           READ_ACP
# s3:GetBucketPolicy                 READ_ACP
# s3:GetBucketRequestPayment         READ_ACP
# s3:GetBucketTagging                READ_ACP
# s3:GetBucketVersioning             READ_ACP
# s3:GetBucketWebsite                READ_ACP
# s3:GetLifecycleConfiguration       READ_ACP
# s3:GetObjectAcl                    READ_ACP
# s3:GetObjectVersionAcl             READ_ACP
# s3:GetReplicationConfiguration     READ_ACP
# s3:DeleteBucketPolicy              WRITE_ACP
# s3:DeleteBucketWebsite             WRITE_ACP
# s3:DeleteReplicationConfiguration  WRITE_ACP
# s3:PutAccelerateConfiguration      WRITE_ACP
# s3:PutBucketAcl                    WRITE_ACP
# s3:PutBucketCORS                   WRITE_ACP
# s3:PutBucketLogging                WRITE_ACP
# s3:PutBucketNotification           WRITE_ACP
# s3:PutBucketPolicy                 WRITE_ACP
# s3:PutBucketRequestPayment         WRITE_ACP
# s3:PutBucketTagging                WRITE_ACP
# s3:PutPutBucketVersioning          WRITE_ACP
# s3:PutBucketWebsite                WRITE_ACP
# s3:PutLifecycleConfiguration       WRITE_ACP
# s3:PutObjectAcl                    WRITE_ACP
# s3:PutObjectVersionAcl             WRITE_ACP
# s3:PutReplicationConfiguration     WRITE_ACP
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
      "Action":["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"],
      "Resource":["arn:aws:s3:::{0}".format(bucket_name), "arn:aws:s3:::{0}/*".format(bucket_name)]
    }
  ]
}

bucket_policy = json.dumps(bucket_policy)
conn.put_bucket_policy(Bucket=bucket_name, Policy=bucket_policy)
