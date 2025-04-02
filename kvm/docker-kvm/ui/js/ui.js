const config = { g_hosts: {} };
function about() { showView('about'); }
function genOption(jsonobj, selectedValue = '') {
  return jsonobj.map(item => {
    return `<option value="${item.name}" ${item.name === selectedValue ? 'selected' : ''}>${item.desc}</option>`;
  }).join('');
}
function filterByKey(array, key, value) {
  return array.filter(item => item[key] === value);
}
function genActBtn(smsg, icon, action, ...args) {
  // args must string
  var str_arg = '';
  if (args.length > 0) {
    str_arg = '"' + args.join('","') + '"';
  }
  return `<button title='${smsg}' onclick='${action}(${str_arg})'><i class="fa ${icon}"></i></button>`;
}
function show_all_db_vms(view) {
  const dbvms = document.getElementById("dbvms");
  const dbvms_total = document.getElementById("dbvms-total");
  getjson('GET', `/vm/list/`, function(resp) {
    const vms = JSON.parse(resp);
    dbvms_total.innerHTML = vms.length;
    var tbl = '';
    vms.forEach(item => {
      const index = config.g_hosts.findIndex(element => element.name === item.kvmhost);
      tbl += `<div class="vms-wrapper">`;
      tbl += `<div class="vms-wrapper-header"><h2>GUEST</h2>`;
      tbl += `<button title='GOTO HOST' onclick='on_menu_host(config.g_hosts, ${index})'><i class="fa fa-cog fa-spin fa-lg"></i></button>`;
      tbl += `</div>`;
      tbl += `<table>`;
      for(const key in item) {
        if(key === 'disks') {
          const disks = JSON.parse(item[key]);
          disks.forEach(disk => {
            tbl += `<tr><th width="25%" title="disk">${disk.dev}</th><td class="truncate">${disk.device}:${disk.type}:${disk.vol}</td></tr>`;
          });
        } else if (key === 'nets') {
          const nets = JSON.parse(item[key]);
          nets.forEach(net => {
            tbl += `<tr><th width="25%" title="net">${net.type}</th><td class="truncate">${net.mac}</td></tr>`;
          });
        } else if (key === 'mdconfig') {
          const mdconfig = JSON.parse(item[key]);
          for(var mdkey in mdconfig) {
            tbl += `<tr><th width="25%">${mdkey}</th><td class="truncate">${mdconfig[mdkey]}</td></tr>`;
          }
        } else {
          tbl += `<tr><th width="25%">${key}</th><td class="truncate">${item[key]}</td></tr>`;
        }
      }
      tbl += "</table>";
      tbl += "</div>";
    });
    dbvms.innerHTML = tbl;
  });
  showView(view);
}
function show_vms(host, vms) {
  var tbl = '';
  vms.forEach(item => {
    tbl += `<div class="vms-wrapper">`;
    tbl += `<div class="vms-wrapper-header vmstate${item.state}"><h2>GUEST</h2><div>`;
    tbl += genActBtn('Show XML', 'fa-file-code-o', 'show_xml', host, item.uuid);
    tbl += genActBtn('Guest UI URL', 'fa-link', 'show_vmui', host, item.uuid);
    if(item.state === 'RUN') {
      tbl += genActBtn('VNC View', 'fa-desktop', 'display', host, item.uuid);
      tbl += genActBtn('Stop VM', 'fa-power-off', 'stop', host, item.uuid);
      tbl += genActBtn('ForceStop VM', 'fa-plug', 'force_stop', host, item.uuid);
    } else {
      tbl += genActBtn('Start VM', 'fa-play', 'start', host, item.uuid);
      tbl += genActBtn('Undefine', 'fa-trash', 'undefine', host, item.uuid);
    } 
    tbl += genActBtn('Add ISO', 'fa-floppy-o', 'add_iso', host, item.uuid);
    tbl += genActBtn('Add NET', 'fa-wifi', 'add_net', host, item.uuid);
    tbl += genActBtn('Add DISK', 'fa-database', 'add_disk', host, item.uuid);
    tbl += `</div></div>`;
    tbl += `<table>`;
    for(const key in item) {
      if(key === 'disks') {
        const disks = JSON.parse(item[key]);
        disks.forEach(disk => {
          tbl += `<tr><th title="${disk.device}">${disk.dev}</th><td colspan="2" class="truncate" title="${disk.vol}">${disk.type}:${disk.vol}</td><td><a title="Remove Disk" href="javascript:del_device('${host}', '${item.uuid}', '${disk.dev}')">Remove</a></td></tr>`;
        });
      } else if (key === 'nets') {
        const nets = JSON.parse(item[key]);
        nets.forEach(net => {
          tbl += `<tr><th>${net.type}</th><td colspan="2" class="truncate" title="${net.mac}">${net.mac}</td><td><a title="Remove netcard" href="javascript:del_device('${host}', '${item.uuid}', '${net.mac}')">Remove</a></td></tr>`;
        });
      } else if (key === 'mdconfig') {
        const mdconfig = JSON.parse(item[key]);
        for(var mdkey in mdconfig) {
          tbl += `<tr><th>${mdkey}</th><td colspan="3">${mdconfig[mdkey]}</td></tr>`;
        }
      } else {
        tbl += `<tr><th>${key}</th><td colspan="3" class="truncate">${item[key]}</td></tr>`;
      }
    }
    tbl += "</table>";
    tbl += "</div>";
  });
  return tbl;
}
function show_host(host) {
  // delete host.last_modified;
  var tbl = '';
  tbl += `<div class="host-wrapper">`;
  tbl += `<div class="host-wrapper-header"><h2>KVM HOST</h2><div>`;
  tbl += genActBtn('Refresh VM List', 'fa-refresh fa-spin', 'vmlist', host.name);
  tbl += genActBtn('Create VM', 'fa-tasks', 'create_vm', host.name, host.arch);
  tbl += `</div></div>`;
  tbl += `<table>`;
  for(var key in host) {
    tbl += `<tr><th width="25%">${key}</th><td>${host[key]}</td></tr>`;
  }
  tbl += '</table>';
  tbl += '</div>';
  return tbl;
}
///////////////////////////////////////////////////////////
// <form id="myform"></form>
// const form = document.getElementById('myform');
// form.addEventListener('submit', function(event) {
//   event.preventDefault(); // Prevents the default form submission
//   const res = getFormJSON(form);
//   console.log(JSON.stringify(res))
// }, { once: true });
function getFormJSON(form) {
  const data = new FormData(form);
  return Object.fromEntries(data.entries());
}
///////////////////////////////////////////////////////////
// .tabContent { display:none; }
// <div id="myview" class="tabContent">...</div>
// <div id="view1" class="tabContent">...</div>
// showView('view1')
function showView(id) {
  var view = document.getElementById(id);
  var tabContents = document.getElementsByClassName('tabContent');
  for (var i = 0; i < tabContents.length; i++) {
    tabContents[i].style.display = 'none';
  }
  if(view != null) { view.style.display = "block"; }
}
function Alert(message) {
  const div_alert = document.getElementById("alert");
  if (div_alert !== null) {
    div_alert.innerHTML = message;
    showView('alert');
  } else {
    alert(message);
  }
}
function dispok(desc) {
  Alert(`
  <div class="form-wrapper">
    <div class="form-wrapper-header success"><h2>SUCCESS</h2><button title="Close" class="close" onclick="showView('hostlist')"><h2>&times;</h2></button></div>
    <form><pre style="white-space: pre-wrap;">${desc}</pre></form>
  </div>`);
}
function disperr(code, name, desc) {
  Alert(`
  <div class="form-wrapper">
    <div class="form-wrapper-header error"><h2>${name}: ${code}</h2><button title="Close" class="close" onclick="showView('hostlist')"><h2>&times;</h2></button></div>
    <form><pre style="white-space: pre-wrap;">${desc}</pre></form>
  </div>`);
}
function toggleOverlay(visible) {
  const overlay = document.getElementById("overlay");
  if (overlay) {
    overlay.style.display = visible ? "block" : "none";
    if (visible) {
      const overlay_output = document.querySelector("#overlay_output");
      overlay_output.innerHTML = "";
    }
  }
}
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
        disperr(xhr.status, `${method} ${url}`, `${xhr.response}`);
      }
    }
    return;
  }
  if(null !== data && typeof data !== 'undefined') {
    xhr.send(JSON.stringify(data));
  } else {
    xhr.send();
  }
  toggleOverlay(true);
}
function vmlist(host) {
  document.getElementById("vms").innerHTML = '';
  getjson('GET', `/vm/list/${host}`, function(res) {
    var vms = JSON.parse(res);
    document.getElementById("vms").innerHTML = show_vms(host, vms);
  });
}
function on_menu_host(host, n) {
  document.getElementById("host").innerHTML = '';
  document.getElementById("host").innerHTML = show_host(host[n]);
  vmlist(host[n].name);
  showView("hostlist");
}
function getjson_result(res) {
  try {
    var result = JSON.parse(res);
    if(result.result === 'OK') {
      var desc = result.desc;
      delete result.result;
      delete result.desc;
      if (Object.keys(result).length === 0) {
        dispok(`${desc}`);
      } else {
        dispok(`${desc} ${JSON.stringify(result)}`);
      }
    } else {
      disperr(result.code, result.name, result.desc);
    }
  } catch (e) {
    disperr(999, `local error`, `${e}, ${res}`);
  }
}
function show_xml(host, uuid) {
  getjson('GET', `/vm/xml/${host}/${uuid}`, function(res) {
    dispok(res.replace(/</g, "&lt;").replace(/>/g, "&gt;"));
  });
}
function setAction(form) {
  const email = document.getElementById('email');
  const url = document.getElementById('url');
  if(email) {
    form.action = `mailto:${email.value}?subject=vm information&body=${url.href}`;
    return true;
  }
  return false;
}
function show_vmui(host, uuid) {
  const form = document.getElementById('vmui_form');
  const vmuimail = document.getElementById('vmuimail');
  form.addEventListener('submit', function(event) {
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    const d = Date.parse(`${res.date} ${res.time}`).valueOf();
    const epoch = Math.floor(d / 1000);
    getjson('GET', `/vm/ui/${host}/${uuid}/${epoch}`, function(resp) {
      var result = JSON.parse(resp);
      if(result.result === 'OK') {
        document.getElementById('expire').value = result.expire;
        document.getElementById('token').value = result.token;
        document.getElementById('url').setAttribute("href", `${result.url}?token=${result.token}`);
      } else {
        disperr(result.code, result.name, result.desc);
      }
    });
  }, { once: true });
  form.reset();
  vmuimail.reset();
  showView('vmui');
}
function start(host, uuid) {
  if (confirm(`Start ${uuid}?`)) {
    getjson('GET', `/vm/start/${host}/${uuid}`, getjson_result, null, null, 60000);
  }
}
function stop(host, uuid) {
  if (confirm(`Stop ${uuid}?`)) {
    getjson('GET', `/vm/stop/${host}/${uuid}`, getjson_result);
  }
}
function force_stop(host, uuid) {
  if (confirm(`Force Stop ${uuid}?`)) {
    getjson('POST', `/vm/stop/${host}/${uuid}`, getjson_result, null, null, 60000);
  }
}
function undefine(host, uuid) {
  if (confirm(`Undefine ${uuid}?`)) {
    getjson('GET', `/vm/delete/${host}/${uuid}`, getjson_result);
  }
}
function display(host, uuid) {
  getjson('GET', `/vm/display/${host}/${uuid}`, function(resp) {
    var result = JSON.parse(resp);
    if(result.result === 'OK') {
      //document.getElementById("display").src = result.display;
      //window.open(result.display, "_blank");
      //getjson_result(resp);
      dispok(`<a target="_blank" style="color: var(--white-color);" title="expire ${result.expire}" href="${result.display}">${result.display}</a>`);
    } else {
      disperr(result.code, result.name, result.desc);
    }
  });
}
function del_device(host, uuid, dev) {
  if (confirm(`delete device /${host}/${uuid}/${dev} ?`)) {
    getjson('POST', `/vm/detach_device/${host}/${uuid}/${dev}`, getjson_result);
  }
}
function create_vm(host, arch) {
  const vm_ip = document.getElementById('vm_ip');
  const vm_gw = document.getElementById('vm_gw');
  getjson('GET', `/vm/freeip/`, function(resp) {
    var ips = JSON.parse(resp);
    vm_ip.value = ips.cidr;
    vm_gw.value = ips.gateway;
  });
  const form = document.getElementById('createvm_form');
  form.addEventListener('submit', function(event) {
    showView('hostlist');
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    getjson('POST', `/vm/create/${host}`, getjson_result , res);
  }, { once: true });
  form.reset();
  showView('createvm');
}
function do_add(host, uuid, res) {
  function getLastLine(str) {
    const lines = str.split('\n');
    return lines[lines.length - 1];
  }
  getjson('POST', `/vm/attach_device/${host}/${uuid}/${res.device}`, function(res) {
    getjson_result(getLastLine(res));
  }, res, function(resp) {
    const overlay_output = document.querySelector("#overlay_output");
    overlay_output.innerHTML = resp; /*overlay_output.innerHTML += resp;*/
    overlay_output.scrollTop=overlay_output.scrollHeight;
  }, 60000); /*add disk 60s timeout*/
}
function add_disk(host, uuid) {
  const form = document.getElementById('adddisk_form');
  const goldlst = document.getElementById('gold_list');
  const devlst = document.getElementById('dev_list');
  getjson('GET', `/tpl/device/${host}`, function(resp) {
    var devs = JSON.parse(resp);
    devlst.innerHTML = genOption(filterByKey(devs, 'devtype', 'disk'));
  });
  getjson('GET', `/tpl/gold/${host}`, function(resp) {
    var gold = JSON.parse(resp);
    goldlst.innerHTML = genOption(gold, '数据盘');
  }, null);
  form.addEventListener('submit', function(event) {
    showView('hostlist');
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    do_add(host, uuid, res);
  }, { once: true });
  form.reset();
  showView('adddisk');
}
function add_net(host, uuid) {
  const form = document.getElementById('addnet_form');
  const netlst = document.getElementById('net_list');
  getjson('GET', `/tpl/device/${host}`, function(resp) {
    var devs = JSON.parse(resp);
    netlst.innerHTML = genOption(filterByKey(devs, 'devtype', 'net'));
  });
  form.addEventListener('submit', function(event) {
    showView('hostlist');
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    do_add(host, uuid, res);
  }, { once: true });
  form.reset();
  showView('addnet');
}
function add_iso(host, uuid) {
  const form = document.getElementById('addiso_form');
  const isolst = document.getElementById('iso_list');
  getjson('GET', `/tpl/device/${host}`, function(resp) {
    var devs = JSON.parse(resp);
    isolst.innerHTML = genOption(filterByKey(devs, 'devtype', 'iso'));
  });
  form.addEventListener('submit', function(event) {
    showView('hostlist');
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    do_add(host, uuid, res);
  }, { once: true });
  form.reset();
  showView('addiso');
}
/* create vm add new meta key/value */
function set_name(r) {
  var i = r.parentNode.parentNode.rowIndex;
  var input = document.getElementById("table_meta_data").rows[i].cells[1].getElementsByTagName('input');
  input[0].name=r.value;
}
function del_meta(r) {
  var i = r.parentNode.parentNode.rowIndex;
  document.getElementById("table_meta_data").deleteRow(i);
}
function add_meta() {
  var tableRef = document.getElementById("table_meta_data");
  var newRow = tableRef.insertRow(-1);
  var c_name = newRow.insertCell(0);
  var c_value = newRow.insertCell(1);
  var del_btn = newRow.insertCell(2);
  c_name.innerHTML = '<input type="text"/ placeholder="name" onChange="set_name(this)" required>';
  c_value.innerHTML = '<input type="text" placeholder="value" required>';
  del_btn.innerHTML = '<input type="button" value="Remove" onclick="del_meta(this)"/>';
}
/* include html */
function includeHTML() {
  const elements = document.querySelectorAll('[w3-include-html]');
  elements.forEach(elmnt => {
    const file = elmnt.getAttribute('w3-include-html');
    if (file) {
      fetch(file).then(response => {
          if (!response.ok) {
            throw new Error('Page not found.');
          }
          return response.text();
        }).then(html => {
          elmnt.innerHTML = html;
          elmnt.removeAttribute('w3-include-html');
          includeHTML(); // Process any remaining elements
        }).catch(error => {
          elmnt.innerHTML = error.message;
        });
    }
  });
}
/* ------------------------- */
window.addEventListener('load', function() {
  includeHTML();
  getjson('GET', '/tpl/host/', function (resp) {
    config.g_hosts = JSON.parse(resp);
    var mainMenu = "";
    for(var n = 0; n < config.g_hosts.length; n++) {
      mainMenu += `<a href='#' class='nav_link sublink' onclick='on_menu_host(config.g_hosts, ${n})'><i class="fa fa-desktop"></i><span>${config.g_hosts[n].name}</span></a>`;
    }
    document.getElementById("sidebar").innerHTML = mainMenu;
  });
})
/* ------------------------- */
function getTheme() {
  return localStorage.getItem('theme') || 'light';
}
function saveTheme(theme) {
  localStorage.setItem('theme', theme);
}
/* ------------------------- */
function getjson_fetch_impl(method, url, callback, data = null, stream = null, timeout = 40000) {
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
        if (done) {
          return;
        }
        const chunk = decoder.decode(value);
        if(stream && typeof(stream) == "function") {
          stream(chunk);
        }
        read(); // Continue reading the stream
      });
    }
    read(); // Start reading the stream
    return responseClone.text();
  }).then(data => {
    clearTimeout(timeoutId);
    if (callback && typeof(callback) == "function") {
      callback(data);
    }
    console.log(data);
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
