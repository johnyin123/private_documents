#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("initver[2021-12-02T12:12:11+08:00]:maven_onejar.sh")
main() {
    echo "REPOSITORY: ~/.m2/repository/"
    mvn archetype:generate -DgroupId=com.mytest -DartifactId=myapp -DarchetypeArtifactId=maven-archetype-quickstart -DinteractiveMode=false
    cat <<'EOF'
  <properties>
    <maven.compiler.source>14</maven.compiler.source>
    <maven.compiler.target>14</maven.compiler.target>
    <junit.version>3.8.1</junit.version>
    <httpclient.version>4.5.3</httpclient.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>${junit.version}</version>
      <scope>test</scope>
    </dependency>
    <dependency>
      <groupId>org.apache.httpcomponents</groupId>
      <artifactId>httpclient</artifactId>
      <version>${httpclient.version}</version>
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
    return 0
}
main "$@"
