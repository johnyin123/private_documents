#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#最后一步生成的object url，通过wget访问时需要把一些特殊字符进行转义；
from __future__ import print_function
import boto3

def main():
    access_key = 'AIOCOC1SP6WB4JLD3Q2U'
    secret_key = 'lVEqs4cDudYvrJDrDOxxAGMRekmLR9KHCAjBDBc7'
    s3_host = 'http://192.168.168.101'

    bucket_name = 'bucket1'
    object_key = 'hello.txt'

    s3client = boto3.client('s3',
        aws_secret_access_key = secret_key,
        aws_access_key_id = access_key,
        endpoint_url = s3_host)
#    response = s3client.list_buckets()
#    for bucket in response['Buckets']:
#        print("Listing owned buckets returns => {0} was created on {1}\n".format(bucket['Name'], bucket['CreationDate']))

    # creating a bucket
    response = s3client.create_bucket(Bucket = bucket_name)
    print("Creating bucket {0} returns => {1}\n".format(bucket_name, response))

    # creating an object
    response = s3client.put_object(Bucket = bucket_name, Key = object_key, Body = 'Hello World!')
    print("Creating object {0} returns => {1}\n".format(object_key, response))

    hello_url = s3client.generate_presigned_url('get_object', Params={'Bucket': bucket_name, 'Key': object_key}, ExpiresIn= 3600)
    print(hello_url)

if __name__ == '__main__':
    main() 


