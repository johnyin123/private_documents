PROXY_CFG=~/proxy.js
[ -r ${PROXY_CFG} ] || {
    cat> ${PROXY_CFG} <<EOF
function FindProxyForURL(url, host)
{
 if (dnsDomainIs(host, "google.com")
  || dnsDomainIs(host, "google.com.hk")
  || dnsDomainIs(host, "t66y.com")
    )
 { return "PROXY 10.0.1.4:8888"; }
 return "DIRECT";
}
EOF
}
google-chrome --proxy-pac-url=file://${PROXY_CFG}
