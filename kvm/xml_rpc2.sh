#!/bin/bash

print_value() {
    case "$1" in
        string:*)  echo '        <param><value><string>'${1##string:}'</string></value></param>' ;;
        i4:*)      echo '        <param><value><i4>'${1##i4:}'</i4></value></param>' ;;
        int:*)     echo '        <param><value><int>'${1##int:}'</int></value></param>' ;;
        boolean:*) echo '        <param><value><boolean>'${1##boolean:}'</boolean></value></param>' ;;
        array:*)
            echo '        <param><value><array><data>'
            for j in $(echo $1 | sed 's/^array:[^ ]*//g' ); do
                echo -n '    '
                print_value "$j" | sed 's/<\/\?param>//g'
            done
            echo '        </data></array></value></param>'
            ;;
        *)         echo '        <param><value>'$1'</value></param>' ;;
    esac
}

CALL="$(
    echo '<?xml version="1.0"?>'
    echo '<methodCall>'
    echo '    <methodName>'$1'</methodName>'
    
    echo '    <params>'
    echo '        <param><value>'$(cat $HOME/.one/one_auth)'</value></param>'
    
    for i in "${@:2}"; do
        print_value "$i"
    done
    
    echo '    </params>'
    echo '</methodCall>'
    CALL=$2
)"

RESPONSE="$(curl -s -k ${ONE_XMLRPC:-http://localhost:2633/RPC2} --data "$CALL")"

echo "<!---------- INPUT ------------>" 
echo
echo "$CALL" | sed 's/<param><value>\([a-zA-Z0-9]\+\):[0-9a-zA-Z-]\+<\/value><\/param>/<param><value>\1:deadbeefdeadbeefdeadbeefdeadbeef<\/value><\/param>/'
echo
echo "<!--------- OUTPUT ------------>"
echo
echo "$RESPONSE"
echo
echo "<!---------- END -------------->"
