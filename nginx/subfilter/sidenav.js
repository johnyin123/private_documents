function openNav() { document.getElementById("mySidenav").style.width = "250px"; }
function closeNav() { document.getElementById("mySidenav").style.width = "0"; }
function appendHtml(el, str) {
  var div = document.createElement('div');
  div.innerHTML = str;
  while (div.children.length > 0) {
    el.appendChild(div.children[0]);
  }
}
var html = `
<div style="position:fixed;top:50%;left:30px;">
<span style="font-size:30px;cursor:pointer;position:absolute;top:50%;" onclick="openNav()">+</span>
</div>
<div id="mySidenav" class="sidenav">
  <a href="javascript:void(0)" class="closebtn" onclick="closeNav()">&times;</a>
  <a href="#">FileDownload</a>
</div>
`
appendHtml(document.body, html);
