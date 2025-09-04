function getjson(method, url, callback, data=null, stream=null, tmout=40000) {
  /* Set default timeout 40 seconds*/
  var xhr = new XMLHttpRequest();
  xhr.onerror = function () { console.error(`${url} ${method} onerror`); disperr(0,`${url}`,`${method} onerror`);};
  xhr.onabort = function() { console.error(`${url} ${method} abort`); disperr(0,`${url}`,`${method} abort`);};
  xhr.ontimeout = function () { console.error(`${url} ${method} timeout`); disperr(0,`${url}`,`${method} timeout`);};
  xhr.onloadend = function() { toggleOverlay(false); /*as finally*/ };
  xhr.open(method, url, true);
  xhr.setRequestHeader('Content-Type', 'application/json');
  xhr.timeout = tmout;
  xhr.onreadystatechange = function() {
    if(this.readyState === 3 && this.status === 200) {
      if (stream && typeof(stream) == "function") {
        stream(xhr.responseText);
      }
      return;
    }
    if(this.readyState === 4 && this.status === 200) {
      if (callback && typeof(callback) == "function") {
        callback(xhr.response);
      }
      return;
    }
    if(xhr.readyState === 4 && xhr.status !== 0) {
      console.error(`${method} ${url} ${xhr.status} ${xhr.response}`);
      try {
        var result = JSON.parse(xhr.response);
        disperr(result.code, result.name, result.desc);
      } catch (e) {
        disperr(xhr.status, `${method} ${url}`, `${xhr.response}, ${e.toString()}`);
      }
    }
    return;
  }
  xhr.send(data ? JSON.stringify(data) : null);
  toggleOverlay(true);
}
