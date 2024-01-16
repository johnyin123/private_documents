#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# apt -y install --no-install-recommends python3 python3-boto3 python3-flask
import os, json, boto3
from flask import Flask, render_template_string, request, make_response, jsonify

app = Flask(__name__)

class S3:
    def __init__(self):
        self.S3_HOST = os.environ.get('S3_HOST', 'http://10.170.24.2')
        # self.S3_HOST = os.environ.get('S3_HOST', 'http://10.170.6.105:9999')
        self.S3_ACCESS_KEY = os.environ.get('S3_ACCESS_KEY', 'admin')
        self.S3_SECRET_KEY = os.environ.get('S3_SECRET_KEY', 'tsd@2023')
        print("HOST={}\nACCESS_KEY={}\nSECRET_KEY={}\n".format(self.S3_HOST,self.S3_ACCESS_KEY,self.S3_SECRET_KEY))
        self.session = boto3.Session(aws_access_key_id=self.S3_ACCESS_KEY, aws_secret_access_key=self.S3_SECRET_KEY)
        self.client = self.session.client("s3", verify=False, use_ssl = False, endpoint_url = self.S3_HOST, config=boto3.session.Config(signature_version='s3v4'),aws_session_token="SESSION_TOKEN")

    def create_bucket(self, bucket):
        response = self.client.create_bucket(Bucket=bucket)
        print(response)

    def delete_bucket(self, bucket):
        response = self.client.delete_bucket(Bucket=bucket)
        print(response)

    def set_policy(self, bucket):
        bucket_policy = {
          "Version":"2012-10-17",
          "Statement":[
            {
              "Sid":"AddPerm",
              "Effect":"Allow",
              "Principal": "*",
              "Action":["s3:ListBucket"],
              "Resource":["arn:aws:s3:::{0}".format(bucket)]
            },
            {
              "Sid":"AddPerm",
              "Effect":"Allow",
              "Principal": "*",
              "Action":["s3:GetObject", "s3:PutObject", "s3:GetObjectAcl", "s3:PutObjectAcl", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:PutBucketCORS"],
              "Resource":["arn:aws:s3:::{0}/*".format(bucket)]
            }
          ]
        }
        bucket_policy = json.dumps(bucket_policy)
        self.client.put_bucket_policy(Bucket=bucket, Policy=bucket_policy)

    def set_acl(self, bucket, acl='public-read'):
        result = self.client.get_bucket_acl(Bucket=bucket)
        print("org permission is {}".format(result))
        response = self.client.put_bucket_acl(ACL=acl, Bucket=bucket)
        result = self.client.get_bucket_acl(Bucket=bucket)
        print("the new permissions for bucket {0} is {1}".format(bucket, result['Grants']))

    def set_cors(self, bucket):
        BUCKET_CORS_CONFIG = {
          "CORSRules": [
            {
              "AllowedOrigins": ["*"],
              "AllowedHeaders": ["*"],
              "AllowedMethods": ["GET", "HEAD", "POST", "PUT", "DELETE"],
              "MaxAgeSeconds": 3600,
              "ExposeHeaders": ["Etag"]
            },
            {
              'AllowedHeaders': [ 'Authorization', ],
              'AllowedMethods': [ 'GET', ],
              'AllowedOrigins': [ '*', ],
              'MaxAgeSeconds': 3600,
            },]
        }
        response = self.client.put_bucket_cors(Bucket=bucket, CORSConfiguration=BUCKET_CORS_CONFIG)
        print(response)

    # presigned post notwork now TODO:::
    def get_presigned_post_url(self, bucket, file_name, file_type, time=3600):
        return self.client.generate_presigned_post(
            Bucket = bucket, Key = file_name, ExpiresIn = time,
            Fields =       {"acl": "public-read",   "Content-Type": file_type},
            Conditions = [ {"acl": "public-read"}, {"Content-Type": file_type}, ]
        )
    def get_presigned_url(self, bucket, file_name, time=3600):
        return self.client.generate_presigned_url(ClientMethod='put_object', ExpiresIn=time, Params={'Bucket': bucket, 'Key': file_name})
    def get_file(self, bucket, key, time=3600):
        return self.client.generate_presigned_url(ClientMethod='get_object', ExpiresIn=time, Params={'Bucket': bucket, 'Key': key})
    def delete_file(self, bucket, key):
        return self.client.delete_object(Bucket=bucket, Key=key)
    def list_bucket(self):
        response = self.client.list_buckets()
        if 'Buckets' in response.keys():
            for bucket in response['Buckets']:
                print(bucket['Name'])
            else:
                print('Empty')
html="""
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>{title}</title></head>
  <body>
    <h1>Welcome!</h1>
    <br>Please select an file
    <input type="file" id="image">
    <br><img id="preview">
<script>
{script}
</script>
</body>
</html>
"""
put_js="""
function upload(file, signed_request, url, done) {
  console.log(signed_request)
  console.log(url)
  var xhr = new XMLHttpRequest()
  xhr.open('PUT', signed_request)
  xhr.setRequestHeader('x-amz-acl', 'public-read')
  xhr.onload = function() {
    if(xhr.status === 200 || xhr.status === 204) { done(); }
    else{ alert("Could not upload file."); }
  }
  xhr.send(file)
}
function sign_request(file, done) {
  var xhr = new XMLHttpRequest()
  xhr.open('GET', '/sign_put?file_name=' + file.name + '&file_type=' + file.type)
  xhr.onreadystatechange = function() {
    if(xhr.readyState === 4 && xhr.status === 200) {
      var response = JSON.parse(xhr.responseText)
      done(response)
    }
  }
  xhr.send()
}
document.getElementById('image').onchange = function() {
  var file = document.getElementById('image').files[0]
  if (!file) { alert('Could not get file.'); return; }
  sign_request(file, function(response) {
    upload(file, response.signed_request, response.url, function() {
      document.getElementById('preview').src = response.url
    })
  })
}
"""
post_js="""
function upload(file, signed_request, url, done) {
  console.log(signed_request)
  console.log(url)
  var xhr = new XMLHttpRequest();
  xhr.open('POST', signed_request.url);
  var postData = new FormData();
  for(key in signed_request.fields){ postData.append(key, signed_request.fields[key]); }
  postData.append('file', file);
  xhr.setRequestHeader('x-amz-acl', 'public-read')
  xhr.onload = function() { if (xhr.status === 200) { done() } }
  xhr.send(postData);
}
function sign_request(file, done) {
  var xhr = new XMLHttpRequest()
  xhr.open('GET', '/sign_post?file_name=' + file.name + '&file_type=' + file.type)
  xhr.onreadystatechange = function() {
    if(xhr.readyState === 4 && xhr.status === 200) {
      var response = JSON.parse(xhr.responseText)
      done(response)
    }
  }
  xhr.send()
}
document.getElementById('image').onchange = function() {
  var file = document.getElementById('image').files[0]
  if (!file) { alert('Could not get file.'); return; }
  sign_request(file, function(response) {
    upload(file, response.signed_request, response.url, function() {
      document.getElementById('preview').src = response.url
    })
  })
}
"""
@app.route('/put', methods=["GET"])
def put():
    return render_template_string(html.format(script=put_js, title="put upload to s3"))

@app.route('/sign_put')
def sign_put():
    file_name = request.args.get('file_name')
    file_type = request.args.get('file_type')
    print("{} {}\n".format(file_name, file_type))
    s3 = S3()
    bucket=os.environ.get('S3_BUCKET', 'public')
    presigned_put = s3.get_presigned_url(bucket, file_name, 3600)
    print({ "signed_request": presigned_put, "url": "{}/{}/{}".format(s3.S3_HOST, bucket, file_name)})
    return { "signed_request": presigned_put, "url": "{}/{}/{}".format(s3.S3_HOST, bucket, file_name)}

@app.route('/post', methods=["GET"])
def post():
    return render_template_string(html.format(script=post_js, title="post upload to s3"))

@app.route('/sign_post/')
def sign_post():
    file_name = request.args.get('file_name')
    file_type = request.args.get('file_type')
    print("{} {}\n".format(file_name, file_type))
    s3 = S3()
    bucket=os.environ.get('S3_BUCKET', 'public')
    presigned_post= s3.get_presigned_post_url(bucket, file_name, file_type)
    print(json.dumps({ 'signed_request': presigned_post, 'url': '%s/%s/%s' % (s3.S3_HOST, bucket, file_name) }))
    return json.dumps({ 'signed_request': presigned_post, 'url': '%s/%s/%s' % (s3.S3_HOST, bucket, file_name) })

if __name__ == '__main__':
    print("First set bucket cors\n")
    app.run(host='0.0.0.0', port=8080) #, debug=True)
"""
cat <<EOF > ~/.s3cfg
[default]
access_key=admin
secret_key=tsd@2023
host_base=10.170.24.2
host_bucket=10.170.24.2/public
use_https=False
EOF
# Create Bucket
s3cmd mb s3://public
s3cmd put test.txt s3://test01
s3cmd ls s3://test01
s3cmd setpolicy policy.json s3://public
s3cmd info s3://public
cat <<'EOF' > public.polic.json
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"AddPerm",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:ListBucket"],
      "Resource":["arn:aws:s3:::BUCKETNAME"]
    },
    {
      "Sid":"AddPerm",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:PutBucketCORS"],
      "Resource":["arn:aws:s3:::BUCKETNAME/*"]
    }
  ]
}
EOF
"""
