//可跨域方案，利用动态插入script元素来让脚本读取、生效
function loadjs(src) {
  // (B1) CREATE NEW <SCRIPT> TAG
  var js = document.createElement("script");
  js.src = src;
  // js.setAttribute("async", "");
  // (B2) OPTIONAL - ON SUCCESSFUL LOAD & ERROR
  js.onload = () => alert("JS loaded");
  js.onerror = e => alert("Error loading JS");
  // (B3) APPEND <SCRIPT> TAG TO <HEAD>
  document.head.appendChild(js);
}
/* ------------------------- */
function getTheme() {
  return localStorage.getItem('theme') || 'light';
}
function saveTheme(theme) {
  localStorage.setItem('theme', theme);
}
/* ------------------------- */
function getjson(method, url, callback, data = null, stream = null, timeout = 120000) {
  const opts = {
      method: method,
      headers: { 'Content-Type': 'application/json', },
      body: data ? JSON.stringify(data) : null,
  };
  toggleOverlay(true);
  const controller = new AbortController();
  fetch(url, { ...opts, signal: controller.signal }).then(response => {
    if (!response.ok) {
      return response.text().then(text => {
        throw new Error(text);
      });
    }
    if(stream && typeof(stream) == "function") {
      const responseClone = response.clone();
      const reader = responseClone.body.getReader();
      const decoder = new TextDecoder();
      function read() {
        reader.read().then(({ done, value }) => {
          if (done) { return; }
          stream(decoder.decode(value));
          read(); // Continue reading the stream
        });
      }
      read(); // Start reading the stream
    }
    return response.text();
  }).then(s_resp => {
    if (callback && typeof(callback) == "function") { callback(s_resp); }
  }).catch(error => {
    console.error(`${method} ${url} ${error.message}`);
    try {
      var result = JSON.parse(error.message);
      disperr(result.code, result.name, result.desc);
    } catch (e) {
      disperr(999, `${method} ${url}`, `${error.message}`);
    }
  }).finally(() => {
    toggleOverlay(false);
  });
}
/* ------------------------- */
async function getjson(method, url, callback = null, data = null, stream_cb = null, timeout = 120000) {
  const opts = {
      method: method,
      headers: { 'Content-Type': 'application/json', },
      body: data ? JSON.stringify(data) : null,
  };
  toggleOverlay(true);
  try {
    const response = await fetch(url, opts);
    if (!response.ok) {
      throw new Error(`HTTP error! ${response.status}`);
    }
    const reader = response.body.getReader();
    const textDecoder = new TextDecoder();
    let receivedData = '';
    while (true) {
      const { done, value } = await reader.read();
      if (done) { break; } //Stream finished
      receivedData += textDecoder.decode(value, { stream: true });
      const lines = receivedData.split('\n');
      receivedData = lines.pop(); // Keep the last incomplete line
      for (const line of lines) {
        if (line) {
          try {
            if(stream_cb && typeof(stream_cb) == "function") { stream_cb(line); }
          } catch (e) {
            console.error('Error:', e);
          }
        }
      }
    }
    if (receivedData) {
      try {
        if (callback && typeof(callback) == "function") { callback(receivedData); }
        return receivedData;
      } catch (e) {
        console.error('Error:', e);
      }
    }
  } catch (error) {
    console.error('Error:', error);
    return null;
  } finally {
    toggleOverlay(false);
  }
}

function cb(resp) { console.log("callback", resp); }
getjson('GET', '/tpl/host/', cb)
// const response = getjson('GET', '/tpl/host/')
// // function streamcb(line) { console.log(line); }
// // const response = getjson('POST', '/vm/attach_device/host01/62a72fe4-3651-4248-b034-2fa00c2f53dd?dev=disk.file', null, {"gold":"debian12","size":2147483648}, streamcb)
// response.then(resp => {
//     console.log('OK==========',resp);
// });

