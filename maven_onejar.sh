#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("b61098e[2021-12-03T12:50:39+08:00]:maven_onejar.sh")
main() {
    local app=${1:-myapp}
    echo "REPOSITORY: ~/.m2/repository/"
    mvn archetype:generate -DgroupId=com.mytest -DartifactId=${app} -DarchetypeArtifactId=maven-archetype-quickstart -DinteractiveMode=false
    cat <<'EOF'
  <properties>
    <maven.compiler.source>14</maven.compiler.source>
    <maven.compiler.target>14</maven.compiler.target>
    <junit.version>3.8.1</junit.version>
    <httpclient.version>3.1</httpclient.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>${junit.version}</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>com.squareup.okhttp3</groupId>
      <artifactId>okhttp</artifactId>
      <version>4.9.3</version>
    </dependency>
  </dependencies>
  <!-- one jar -->
  <build>
    <plugins>
      <plugin>
        <groupId>com.jolira</groupId>
        <artifactId>onejar-maven-plugin</artifactId>
        <version>1.4.4</version>
        <executions>
          <execution>
            <goals>
              <goal>one-jar</goal>
            </goals>
          </execution>
        </executions>
      </plugin>
      <!-- Make this jar executable -->
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-jar-plugin</artifactId>
        <configuration>
          <archive>
            <manifest>
              <mainClass>com.mytest.App</mainClass>
            </manifest>
          </archive>
        </configuration>
      </plugin>
    </plugins>
  </build>
EOF
    mvn package
    echo "build a sprintboot app"
    echo "https://start.spring.io/"
    return 0
}
main "$@"
