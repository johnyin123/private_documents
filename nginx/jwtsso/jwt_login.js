function GetURLParameter(name) {
 var url = window.location.search.substring(1);
 var vars = url.split("&");
 for (var i = 0; i < vars.length; i++) {
  var parm = vars[i].split("=");
  if (parm[0] == name) {
   return parm[1];
  }
 }
 return "";
}
const form=document.getElementById("jwtForm");
const login = "/api/login";
var caller = GetURLParameter("return_url");
form.addEventListener("submit", function(ev) {
 ev.preventDefault();
 var params = new FormData(document.getElementById("jwtForm"));
 var jstr = JSON.stringify(Object.fromEntries(params.entries()));
 fetch(login, { method: "POST", body: jstr }).then(resp => {
  if (!resp.ok) { throw new Error("status:"+resp.status); }
  return resp.json();
 }).then(res => {
  document.cookie = "token="+res.token+";";
  if (caller.length === 0) { caller="/"; }
  location.href=caller;
  return;
 }).catch(error => {
  alert("Error:"+error);
 });
}, { once: true });
