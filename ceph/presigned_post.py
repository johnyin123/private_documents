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
        self.S3_BUCKET = os.environ.get('S3_BUCKET', 'public')
        self.S3_ACCESS_KEY = os.environ.get('S3_ACCESS_KEY', 'admin')
        self.S3_SECRET_KEY = os.environ.get('S3_SECRET_KEY', 'tsd@2023')
        print("HOST={}\nBUCKET={}\nACCESS_KEY={}\nSECRET_KEY={}\n".format(self.S3_HOST,self.S3_BUCKET,self.S3_ACCESS_KEY,self.S3_SECRET_KEY))
        self.client = boto3.client("s3", verify=False, use_ssl = False,
                                   aws_access_key_id=self.S3_ACCESS_KEY,
                                   aws_secret_access_key=self.S3_SECRET_KEY,
                                   endpoint_url = self.S3_HOST,
                                   config=boto3.session.Config(signature_version='s3v4')
                                   )
        # if not self.client.Bucket(bucket).creation_date:
        #     self.client.create_bucket(Bucket=bucket)
        # Delete: self.client.delete_bucket(Bucket=bucket_name)
    def set_cors(self):
        BUCKET_CORS_CONFIG = {
          "CORSRules": [{
              "AllowedOrigins": ['"{}"'.format('http://192.168.169.192:8080')],
              "AllowedHeaders": ["*"],
              "AllowedMethods": ["GET", "HEAD", "POST", "PUT", "DELETE"],
              "MaxAgeSeconds": 3000,
              "ExposeHeaders": ["Etag"]
            }]
        }
        print("set cors")
        self.client.put_bucket_cors(Bucket=self.S3_BUCKET, CORSConfiguration=BUCKET_CORS_CONFIG)
    # presigned post notwork now TODO:::
    def get_presigned_post_url(self, file_name, file_type, time=3600):
        return self.client.generate_presigned_post(
            Bucket = self.S3_BUCKET, Key = file_name, ExpiresIn = time,
            Fields =       {"acl": "public",   "Content-Type": file_type},
            Conditions = [ {"acl": "public"}, {"Content-Type": file_type}, ]
        )
    def get_presigned_url(self, key, time=3600):
        return self.client.generate_presigned_url(ClientMethod='put_object', ExpiresIn=time, Params={'Bucket': self.S3_BUCKET, 'Key': key})
    def get_file(self, key, time=3600):
        return self.client.generate_presigned_url(ClientMethod='get_object', ExpiresIn=time, Params={'Bucket': self.S3_BUCKET, 'Key': key})
    def delete_file(self, key):
        return self.client.delete_object(Bucket=self.S3_BUCKET, Key=key)
    def list_bucket(self):
        response = self.client.list_buckets()
        if 'Buckets' in response.keys():
            for bucket in response['Buckets']:
                print(bucket['Name'])
            else:
                print('Empty')
# app.config.from_file("config.json", load=json.load)
index_html="""
<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><title>{{ title }}</title></head>
<body>
<input type="file" id="file_input"/>
<img id="preview" src="" />
<form method="POST" action="/form/">
  <input type="submit" value="Upload">
</form>
<script>
(function() {
  document.getElementById("file_input").onchange = function(){
    var files = document.getElementById("file_input").files;
    var file = files[0];
    if(!file){ return alert("No file selected."); }
    getSignedRequest(file);
  };
})();
</script>
<script>
function getSignedRequest(file){
  var xhr = new XMLHttpRequest();
  xhr.open("GET", "/sign_s3?file_name="+file.name+"&file_type="+file.type);
  xhr.onreadystatechange = function(){
    if(xhr.readyState === 4){
      if(xhr.status === 200){
        var response = JSON.parse(xhr.responseText);
        uploadFile(file, response.data, response.url);
      }
      else{ alert("Could not get signed URL."); }
    }
  };
  xhr.send();
}
function uploadFile(file, s3Data, url){
  var xhr = new XMLHttpRequest();
  xhr.open("POST", s3Data.url);
  var postData = new FormData();
  for(key in s3Data.fields){ postData.append(key, s3Data.fields[key]); }
  postData.append('file', file);
  xhr.onreadystatechange = function() {
    if(xhr.readyState === 4){
      if(xhr.status === 200 || xhr.status === 204){
        document.getElementById("preview").src = url;
      }
      else{ alert("Could not upload file."); }
   }
  };
  xhr.send(postData);
  xhr.onload = function(e) {
    var xhr = e.target;
    console.log(xhr.responseText);
  }
}
</script>
</body>
</html>
"""
@app.route('/', methods=["GET"])
def index():
    return render_template_string(index_html, title="upload to s3")

@app.route('/sign_s3/')
def sign_s3():
    file_name = request.args.get('file_name')
    file_type = request.args.get('file_type')
    print("{} {}\n".format(file_name, file_type))
    s3 = S3()
    # s3.set_cors()
    presigned_post = s3.get_presigned_post_url(file_name, file_type)
    print(json.dumps({
        'data': presigned_post,
        'url': '%s/%s/%s' % (s3.S3_HOST, s3.S3_BUCKET, file_name)
    }))
    return json.dumps({
        'data': presigned_post,
        'url': '%s/%s/%s' % (s3.S3_HOST, s3.S3_BUCKET, file_name)
    })

if __name__ == '__main__':
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
