/* ------------------------- */
function getTheme() {
  return localStorage.getItem('theme') || 'light';
}
function saveTheme(theme) {
  localStorage.setItem('theme', theme);
}
/* ------------------------- */
function getjson(method, url, callback, data = null, stream = null, timeout = 40000) {
  const opts = {
      method: method,
      headers: { 'Content-Type': 'application/json', },
      body: data ? JSON.stringify(data) : null,
  };
  toggleOverlay(true);
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeout);
  fetch(url, { ...opts, signal: controller.signal }).then(response => {
    if (!response.ok) {
      return response.text().then(text => {
        throw new Error(text);
      });
    }
    const responseClone = response.clone();
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    function read() {
      reader.read().then(({ done, value }) => {
        if (done) { return; }
        const chunk = decoder.decode(value);
        if(stream && typeof(stream) == "function") { stream(chunk); }
        read(); // Continue reading the stream
      });
    }
    read(); // Start reading the stream
    return responseClone.text();
  }).then(data => {
    clearTimeout(timeoutId);
    if (callback && typeof(callback) == "function") { callback(data); }
  }).catch(error => {
    clearTimeout(timeoutId);
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
