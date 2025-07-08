<form onsubmit="return load()">
  <input type="text" id="user-name" placeholder="Name" value="USER" required>
  <input type="password" id="user-pass" placeholder="Password" value="PASS" required>
  <input type="submit" value="Load!">
</form>
<script>
function load () {
  // if (window.btoa === undefined) { LOAD POLYFILL }
  var name = document.getElementById("user-name").value,
      pass = document.getElementById("user-pass").value,
      token = "Basic " + window.btoa(name + ":" + pass);
  var xhr = new XMLHttpRequest();
  xhr.open("GET", "protected/secret.html");
  xhr.setRequestHeader("Authorization", token);
  xhr.onload = function(){
    if (this.status==200) {
      document.getElementById("load-here").innerHTML = this.response;
    } else {
      alert("HTTP ERROR " + this.status);
    }
  };
  xhr.send();
  return false;
}
</script>

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
