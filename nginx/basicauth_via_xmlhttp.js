// Basic HTTP Authentication over XMLHttpRequest
var url = 'http://someurl.com';
xml = new XMLHttpRequest();
xml.open("GET", url, false, "username", "password");
xml.onreadystatechange = function() {
  if (xml.readyState != 4) { return; }
  if (xml.status != 200) {
    alert("error");
    return;
  } 
  alert(xml.responseText);
};
xml.send(null);
