function httpfile_exists(url, callback) {
  const xhr = new XMLHttpRequest();
  xhr.open('HEAD', url, true);
  xhr.onreadystatechange = function() {
    if (xhr.readyState === 4) {
      callback(xhr.status === 200);
    }
  };
  xhr.send();
}
httpfile_exists('https://example.com/path/to/your/file.css', function(exists) {
  if (exists) {
    console.log('CSS file exists!');
  } else {
    console.log('CSS file does not exist.');
  }
});
<html>
    <header>
    </header>
    <body>
        <script>
async function getRecursiveFiles(uri) {
    const response = await fetch(uri);
    const items = await response.json();
    let files = [];
    for (const item of items) {
        const itemName = item.name; 
        const itemUri = uri + encodeURIComponent(itemName); 
        if (item.type === "file") {
            files.push(itemUri);
        } else if (item.type === "directory") {
            files = files.concat(await getRecursiveFiles(itemUri + "/")); 
        }
    }
    return files;
}
getRecursiveFiles('/0')
    .then(files => console.log(files))
    .catch(error => console.error("Error fetching files:", error));
        </script>
    </body>
</html>
