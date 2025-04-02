function GetURLParameter(name) {
 const parms = new URLSearchParams(window.location.search);
 return parms.has(name) ? parms.get(name) : "";
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
