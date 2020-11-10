#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> ${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
cat <<'EOF'
{
    "app1": {
        "release": "1.2.00",
        "sshuser": "root",
        "sshaddr": "10.32.147.16",
        "sshport": 60022,
        "depends": [ "app3", "app5"],
        "tomcat": {
            "CATALINA_HOME":"/storage/tomcat-xxxapp",
            "NAME":"xxxapp",
            "PORT":8080,
            "REDIR_PORT":8443,
            "APPBASE":"webapps",
            "JAVA_HOME":"/storage/jdk1.7",
            "XMS":"1024M",
            "XMX":"2048M"
        },
        "application": {
            "local_file":"a.tar.gz"
        }
    }
}
EOF
cat <<'EOF'
<?xml version='1.0' encoding='utf-8'?>
<Server port="9005" shutdown="SHUTDOWN">
  <!--APR library loader. Documentation at /docs/apr.html -->
  <Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />
  <!--Initialize Jasper prior to webapps are loaded. Documentation at /docs/jasper-howto.html -->
  <Listener className="org.apache.catalina.core.JasperListener" />
  <!-- Prevent memory leaks due to use of particular java/javax APIs-->
  <Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />
  <Listener className="org.apache.catalina.mbeans.GlobalResourcesLifecycleListener" />
  <Listener className="org.apache.catalina.core.ThreadLocalLeakPreventionListener" />

  <GlobalNamingResources>
    <Resource name="UserDatabase" auth="Container"
              type="org.apache.catalina.UserDatabase"
              description="User database that can be updated and saved"
              factory="org.apache.catalina.users.MemoryUserDatabaseFactory"
              pathname="conf/tomcat-users.xml" />
  </GlobalNamingResources>
  <!--multi Service !!! -->
  <Service name="{{NAME}}">
      <Connector port="{{PORT}}" redirectPort="{{REDIR_PORT}}" connectionTimeout="20000" protocol="org.apache.coyote.http11.Http11NioProtocol" URIEncoding="UTF-8"/> 
    <Engine name="Catalina" defaultHost="localhost">
      <Realm className="org.apache.catalina.realm.LockOutRealm">
        <Realm className="org.apache.catalina.realm.UserDatabaseRealm" resourceName="UserDatabase"/>
      </Realm>
      <Host name="localhost" appBase="{{APPBASE}}" unpackWARs="true" autoDeploy="true">
        <Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs"
               prefix="access.{{NAME}}." suffix=".txt" pattern="%{X-Forwarded-For}i %l %u %t %r %s %b %T " resolveHosts="false"/>
      </Host>
    </Engine>
  </Service>

</Server>
EOF

cat <<'EOF'
JAVA_HOME={{JAVA_HOME}}
#add pid file
CATALINA_PID="$CATALINA_BASE/tomcat.pid"
#add JVM Options
JAVA_OPTS="-server -XX:PermSize=256M -XX:MaxPermSize=1024M -Xms{{XMS}} -Xmx{{XMX}} -XX:MaxNewSize=256M -Djava.net.preferIPv4Stack=true"
EOF
main() {
    jsonstr="$(cat conf.json)"
    while IFS='' read -r line; do
        echo " ======= ${line} ========"
        release=$(json_config ".${line}.release" <<< "${jsonstr}")
        sshuser=$(json_config ".${line}.sshuser" <<< "${jsonstr}")
        sshaddr=$(json_config ".${line}.sshaddr" <<< "${jsonstr}")
        sshport=$(json_config ".${line}.sshport" <<< "${jsonstr}")
        depends=$(json_config ".${line}.depends[]" <<< "${jsonstr}")
        tomcat_CATALINA=$(json_config ".${line}.tomcat.CATALINA_HOME" <<< "${jsonstr}")
        tomcat_NAME=$(json_config ".${line}.tomcat.NAME" <<< "${jsonstr}")
        tomcat_PORT=$(json_config ".${line}.tomcat.PORT" <<< "${jsonstr}")
        tomcat_REDIR_PORT=$(json_config ".${line}.tomcat.REDIR_PORT" <<< "${jsonstr}")
        tomcat_APPBASE=$(json_config ".${line}.tomcat.APPBASE" <<< "${jsonstr}")
        tomcat_JAVA_HOME=$(json_config ".${line}.tomcat.JAVA_HOME" <<< "${jsonstr}")
        tomcat_XMS=$(json_config ".${line}.tomcat.XMS" <<< "${jsonstr}")
        tomcat_XMX=$(json_config ".${line}.tomcat.XMX" <<< "${jsonstr}")
        cat <<EOF
ssh -p${sshport} ${sshuser}@${sshaddr} "mkdir -p ${tomcat_JAVA_HOME}"
cat jdk1.7.0_75-b13.tar.gz | ssh -p${sshport} ${sshuser}@${sshaddr} "tar -C ${tomcat_JAVA_HOME} -xz"
ssh -p${sshport} ${sshuser}@${sshaddr} "mkdir -p ${tomcat_CATALINA}/${tomcat_APPBASE}"
cat tomcat-7.0.85.tar.gz | ssh -p${sshport} ${sshuser}@${sshaddr} "tar -C ${tomcat_CATALINA} -xz"
sed -e 's|{{XMS}}|${tomcat_XMS}|g;s|{{XMX}}|${tomcat_XMX}|g;s|{{JAVA_HOME}}|${tomcat_JAVA_HOME}|g' setenv.sh.tpl | ssh -p${sshport} ${sshuser}@${sshaddr} "cat > ${tomcat_CATALINA}/bin/setenv.sh"
sed -e 's|{{NAME}}|${tomcat_NAME}|g;s|{{PORT}}|${tomcat_PORT}|g;s|{{REDIR_PORT}}|${tomcat_REDIR_PORT}|g;s|{{APPBASE}}|${tomcat_APPBASE}|g' server.xml.tpl | ssh -p${sshport} ${sshuser}@${sshaddr} "cat > ${tomcat_CATALINA}/conf/server.xml"
EOF
    done < <(jq 'keys[]' <<< "${jsonstr}")
    return 0
}
main "$@"
