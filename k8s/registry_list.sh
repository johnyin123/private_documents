repo=http://registry.local
for pkg in $(curl --silent --insecure --show-error ${repo}/v2/_catalog | jq -r .repositories[]); do
    for tag in $(curl --silent --insecure --show-error ${repo}/v2/${pkg}/tags/list | jq -r .tags[]); do
        echo "${pkg}:${tag}"
        # [ "${pkg}:${tag}" = "elbprovider:0.1-arm64" ] && {
        #     sleep 0.1 && sha256=$(curl --silent --insecure --show-error -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -o /dev/null -w '%header{Docker-Content-Digest}' ${repo}/v2/${pkg}/manifests/${tag})
        #     echo "DEL===================================="
        #     sleep 0.1 && curl --silent --show-error -X DELETE ${repo}/v2/${pkg}/manifests/${sha256}
        # }
    done
done
