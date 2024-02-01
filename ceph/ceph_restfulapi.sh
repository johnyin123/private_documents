ceph_dashboard="https://172.16.16.3:8443"
token=$(curl -s -k -X POST "${ceph_dashboard}/api/auth" \
-H  "Accept: application/vnd.ceph.api.v1.0+json" \
-H  "Content-Type: application/json" \
-d '{"username": "admin", "password": "password"}' | jq -r .token)

echo ${token}

cmd=/api/health/full
curl -s -k -X GET "${ceph_dashboard}${cmd}" \
-H  "Accept: application/vnd.ceph.api.v1.0+json" \
-H  "Content-Type: application/json" \
-H  "Authorization: Bearer ${token}"
