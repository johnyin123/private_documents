const config = { g_hosts: {}, g_host:'', g_vm:'', g_dev:'' };
function curr_host() { return config.g_host; }
function curr_vm() { return config.g_vm; }
function curr_dev() { return config.g_dev; }
function set_curr(kvmhost, uuid='', dev='') { config.g_host = kvmhost; config.g_vm = uuid; config.g_dev = dev; console.info(config.g_host, config.g_vm, config.g_dev);}
function getHost(kvmhost) { return config.g_hosts.find(el => el.name === kvmhost); }
function genOption(jsonobj, selectedValue = '') {
  return jsonobj.map(item => {
    return `<option value="${item.name}" ${item.desc === selectedValue ? 'selected' : ''}>${item.desc}</option>`;
  }).join('');
}
function filterByKey(array, key, value) {
  return array.filter(item => item[key] === value);
}
function getFormJSON(form) {
  const data = new FormData(form);
  form.reset();
  return Object.fromEntries(data.entries());
}
function showView(id) {
  const view = document.getElementById(id);
  const tabContents = document.getElementsByClassName('tabContent');
  Array.from(tabContents).forEach(content => content.style.display = 'none');
  if (view) view.style.display = 'block';
}
function genActBtn(btn=true, smsg, icon, action, kvmhost, args={}) {
  // args must string
  var str_arg = `"${kvmhost}"`;
  for(const key in args) {
      str_arg += `,"${args[key]}"`;
  }
  if(btn == true) {
    return `<button title='${smsg}' onclick='${action}(${str_arg})'><i class="fa ${icon}"></i></button>`;
  }
  return `<a title='${smsg}' href='#' onclick='${action}(${str_arg})')'>${icon}<a>`;
}
function genWrapper(clazz, title, buttons, table) {
  return `<div class="${clazz}">
  <div class="${clazz}-header">${title}<div>${buttons}</div></div>
  ${table}</div>`;
}
function genVmTblItems(item, host = null) {
  const colspan= host ? 2 : 3;
  var tbl = '<table>';
  for(const key in item) {
    if(key === 'disks') {
      const disks = JSON.parse(item[key]);
      disks.forEach(disk => {
        tbl += `<tr><th title="${disk.device}">${disk.dev}</th><td colspan="${colspan}" class="truncate" title="${disk.vol}">${disk.type}:${disk.vol}</td>`;
        var change_media = '';
        if(disk.device === 'cdrom') {
          change_media = genActBtn(false, 'Change Media', 'Change', 'change_iso', host, {'uuid':item.uuid, 'dev':disk.dev});
        }
        var remove_btn = genActBtn(false, 'Remove Disk', 'Remove', 'del_device', host, {'uuid':item.uuid, 'dev':disk.dev});
        tbl += host ? `<td>${remove_btn}${change_media}</td></tr>` : `</tr>`;
      });
    } else if (key === 'nets') {
      const nets = JSON.parse(item[key]);
      nets.forEach(net => {
        tbl += `<tr><th>${net.type}</th><td colspan="${colspan}" class="truncate" title="${net.mac}">${net.mac}</td>`;
        var remove_btn = genActBtn(false, 'Remove netcard', 'Remove', 'del_device', host, {'uuid':item.uuid, 'dev':net.mac});
        tbl += host ? `<td>${remove_btn}</td></tr>`: `</tr>`;
      });
    } else if (key === 'mdconfig') {
      const mdconfig = JSON.parse(item[key]);
      for(var mdkey in mdconfig) {
        tbl += `<tr><th>${mdkey}</th><td colspan="3" class="truncate">${mdconfig[mdkey]}</td></tr>`;
      }
    } else {
      tbl += `<tr><th>${key}</th><td colspan="3" class="truncate">${item[key]}</td></tr>`;
    }
  }
  tbl += '</table>';
  return tbl;
}
function show_all_db_vms(view) {
  const dbvms = document.getElementById("dbvms");
  const dbvms_total = document.getElementById("dbvms-total");
  getjson('GET', `/vm/list/`, function(resp) {
    var tbl = '';
    const vms = JSON.parse(resp);
    dbvms_total.innerHTML = vms.length;
    vms.forEach(item => {
      const btn = `<button title='GOTO HOST' onclick='on_menu_host("${item.kvmhost}")'><i class="fa fa-cog fa-spin fa-lg"></i></button>`;
      const table = genVmTblItems(item);
      tbl += genWrapper("vms-wrapper", "<h2>GUEST</h2>", btn, table);
    });
    dbvms.innerHTML = tbl;
  });
  showView(view);
}
function show_vms(kvmhost, vms) {
  var tbl = '';
  vms.forEach(item => {
    var btn = genActBtn(true, 'Show XML', 'fa-file-code-o', 'show_xml', kvmhost, {'uuid':item.uuid});
    btn += genActBtn(true, 'Guest Admin UI', 'fa-ambulance', 'show_vmui', kvmhost, {'uuid':item.uuid});
    if(item.state === 'RUN') {
      btn += genActBtn(true, 'Console', 'fa-terminal', 'ttyconsole', kvmhost, {'uuid':item.uuid});
      btn += genActBtn(true, 'VNC View', 'fa-desktop', 'display', kvmhost, {'uuid':item.uuid});
      btn += genActBtn(true, 'Reset VM', 'fa-refresh', 'reset', kvmhost, {'uuid':item.uuid});
      btn += genActBtn(true, 'Stop VM', 'fa-power-off', 'stop', kvmhost, {'uuid':item.uuid});
      btn += genActBtn(true, 'ForceStop VM', 'fa-plug', 'force_stop', kvmhost, {'uuid':item.uuid});
    } else {
      btn += genActBtn(true, 'Start VM', 'fa-play', 'start', kvmhost, {'uuid':item.uuid});
      btn += genActBtn(true, 'Undefine', 'fa-trash', 'undefine', kvmhost, {'uuid':item.uuid});
    } 
    btn += genActBtn(true, 'Add CDROM', 'fa-floppy-o', 'add_cdrom', kvmhost, {'uuid':item.uuid});
    btn += genActBtn(true, 'Add NET', 'fa-wifi', 'add_net', kvmhost, {'uuid':item.uuid});
    btn += genActBtn(true, 'Add DISK', 'fa-database', 'add_disk', kvmhost, {'uuid':item.uuid});
    const table = genVmTblItems(item, kvmhost);
    const title = item.state == "RUN" ?  '<h2 class="running">GUEST</h2>' : '<h2>GUEST</h2>';
    tbl += genWrapper("vms-wrapper", title, btn, table);
  });
  return tbl;
}
function show_host(kvmhost) {
  var host = getHost(kvmhost)
  var btn = genActBtn(true, 'Refresh VM List', 'fa-refresh fa-spin', 'vmlist', host.name);
  btn += genActBtn(true, 'Create VM', 'fa-tasks', 'create_vm', host.name);
  const table = genVmTblItems(host);
  return genWrapper('host-wrapper', '<h2>KVM HOST</h2>', btn, table);
}
function Alert(type, title, message) {
  const div_alert = document.getElementById("alert");
  if (div_alert) {
    const btn = `<button title="Close" class="close" onclick="showView('hostlist')"><h2>&times;</h2></button>`;
    const table = `<form><pre style="white-space: pre-wrap;">${message}</pre></form>`;
    div_alert.innerHTML = genWrapper('form-wrapper', `<h2 class="${type}">${title}</h2>`, btn, table);
    showView('alert');
  } else {
    alert(message);
  }
}
function dispok(desc) {
  Alert('success', 'SUCCESS', desc);
}
function disperr(code, name, desc) {
  Alert('error', `${name}: ${code}`, desc);
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
  }).then(data => {
    if (callback && typeof(callback) == "function") { callback(data); }
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
function vmlist(kvmhost) {
  set_curr(kvmhost);
  document.getElementById("vms").innerHTML = '';
  getjson('GET', `/vm/list/${kvmhost}`, function(res) {
    document.getElementById("vms").innerHTML = show_vms(kvmhost, JSON.parse(res));
  });
}
function on_menu_host(kvmhost) {
  document.getElementById("host").innerHTML = show_host(kvmhost);
  vmlist(kvmhost);
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
    disperr(999, `local error`, `${e.toString()}, ${res}`);
  }
}
function show_xml(host, uuid) {
  set_curr(host, uuid);
  getjson('GET', `/vm/xml/${host}/${uuid}`, function(res) {
    Alert('success', `XMLDesc`, res.replace(/</g, "&lt;").replace(/>/g, "&gt;"));
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
function on_vmui(form) {
  showView('vmuimail');
  const res = getFormJSON(form);
  const epoch = Math.floor(Date.parse(`${res.date} ${res.time}`).valueOf() / 1000);
  getjson('GET', `/vm/ui/${curr_host()}/${curr_vm()}?epoch=${epoch}`, function(resp) {
    var result = JSON.parse(resp);
    if(result.result === 'OK') {
      document.getElementById('email').value = '';
      document.getElementById('expire').value = result.expire;
      document.getElementById('token').value = result.token;
      var url = document.getElementById('url');
      url.setAttribute("href", `${result.url}?token=${result.token}`);
      url.innerHTML = `UUID:${curr_vm()}`;
    } else {
      disperr(result.code, result.name, result.desc);
    }
  });
  return false;
}
function show_vmui(host, uuid) {
  set_curr(host, uuid);
  showView('vmui');
}
function start(host, uuid) {
  set_curr(host, uuid);
  if (confirm(`Start ${uuid}?`)) {
    getjson('GET', `/vm/start/${host}/${uuid}`, getjson_result);
  }
}
function reset(host, uuid) {
  set_curr(host, uuid);
  if (confirm(`Reset ${uuid}?`)) {
    getjson('GET', `/vm/reset/${host}/${uuid}`, getjson_result);
  }
}
function stop(host, uuid, force=false) {
  set_curr(host, uuid);
  if (confirm(`${force ? 'Force ' : ''}Stop ${uuid}?`)) {
    getjson('GET', `/vm/stop/${host}/${uuid}${force ? '?force=true' : ''}`, getjson_result);
  }
}
function force_stop(host, uuid) {
  stop(host, uuid, true);
}
function undefine(host, uuid) {
  set_curr(host, uuid);
  if (confirm(`Undefine ${uuid}?`)) {
    getjson('GET', `/vm/delete/${host}/${uuid}`, getjson_result);
  }
}
function ttyconsole(host, uuid) {
  set_curr(host, uuid);
  getjson('GET', `/vm/console/${host}/${uuid}`, function(resp) {
    var result = JSON.parse(resp);
    if(result.result === 'OK') {
      window.open(result.display, "_blank");
    } else {
      disperr(result.code, result.name, result.desc);
    }
  });
}
function display(host, uuid) {
  set_curr(host, uuid);
  getjson('GET', `/vm/display/${host}/${uuid}`, function(resp) {
    var result = JSON.parse(resp);
    if(result.result === 'OK') {
      //document.getElementById("display").src = result.display;
      window.open(result.display, "_blank");
    } else {
      disperr(result.code, result.name, result.desc);
    }
  });
}
function del_device(host, uuid, dev) {
  set_curr(host, uuid, dev);
  if (confirm(`delete device /${host}/${uuid}/${dev} ?`)) {
    getjson('POST', `/vm/detach_device/${host}/${uuid}?dev=${dev}`, getjson_result);
  }
}
function on_changeiso(form) {
  showView('hostlist');
  getjson('POST', `/vm/cdrom/${curr_host()}/${curr_vm()}?dev=${curr_dev()}`, getjson_result, getFormJSON(form));
  return false;
}
function change_iso(host, uuid, dev) {
  set_curr(host, uuid, dev);
  showView('changecdrom');
  getjson('GET', `/tpl/iso/`, function(resp) {
    document.getElementById('isoname_list').innerHTML = genOption(JSON.parse(resp));
  });
}
function on_createvm(form) {
  showView('hostlist');
  getjson('POST', `/vm/create/${curr_host()}`, getjson_result, getFormJSON(form));
  return false;
}
function create_vm(host) {
  set_curr(host);
  showView('createvm');
  document.getElementById('table_meta_data').innerHTML = '';
  getjson('GET', `/vm/freeip/`, function(resp) {
    var ips = JSON.parse(resp);
    document.getElementById('vm_ip').value = ips.cidr;
    document.getElementById('vm_gw').value = ips.gateway;
  });
}
function on_add(form) {
  function getLastLine(str) {
    const lines = str.split('\n');
    return lines[lines.length - 1];
  }
  const res = getFormJSON(form);
  getjson('POST', `/vm/attach_device/${curr_host()}/${curr_vm()}?dev=${res.device}`, function(res) {
    getjson_result(getLastLine(res));
  }, res, function(resp) {
    const overlay_output = document.querySelector("#overlay_output");
    overlay_output.innerHTML += resp; /*overlay_output.innerHTML = resp;*/
    overlay_output.scrollTop=overlay_output.scrollHeight;
  }, 600000); /*add disk 10m timeout*/
  return false;
}
function add_disk(host, uuid) {
  set_curr(host, uuid);
  showView('adddisk');
  getjson('GET', `/tpl/device/${host}`, function(resp) {
    document.getElementById('dev_list').innerHTML = genOption(filterByKey(JSON.parse(resp), 'devtype', 'disk'));
  });
  getjson('GET', `/tpl/gold/${host}`, function(resp) {
    document.getElementById('gold_list').innerHTML = genOption(JSON.parse(resp), '数据盘');
  });
}
function add_net(host, uuid) {
  set_curr(host, uuid);
  showView('addnet');
  getjson('GET', `/tpl/device/${host}`, function(resp) {
    document.getElementById('net_list').innerHTML = genOption(filterByKey(JSON.parse(resp), 'devtype', 'net'));
  });
}
function add_cdrom(host, uuid) {
  set_curr(host, uuid);
  showView('addcdrom');
  getjson('GET', `/tpl/device/${host}`, function(resp) {
    document.getElementById('cdrom_list').innerHTML = genOption(filterByKey(JSON.parse(resp), 'devtype', 'iso'));
  });
}
/* create vm add new meta key/value */
function set_name(r) {
  var i = r.parentNode.parentNode.rowIndex;
  var input = document.getElementById("table_meta_data").rows[i].cells[1].getElementsByTagName('input');
  input[0].name=r.value;
}
function del_meta(r) {
  document.getElementById("table_meta_data").deleteRow(r.parentNode.parentNode.rowIndex);
}
function add_meta() {
  var newRow = document.getElementById("table_meta_data").insertRow(-1);
  var c_name = newRow.insertCell(0);
  var c_value = newRow.insertCell(1);
  var del_btn = newRow.insertCell(2);
  c_name.innerHTML = '<input type="text" maxlength="10" placeholder="name" onChange="set_name(this)" required>';
  c_value.innerHTML = '<input type="text" maxlength="50" placeholder="value" required>';
  del_btn.innerHTML = '<input type="button" value="Remove" onclick="del_meta(this)"/>';
}
/* include html */
function includeHTML() {
  document.querySelectorAll('[w3-include-html]').forEach(elmnt => {
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
    config.g_hosts.forEach(host => {
      mainMenu += `<a href='#' class='nav_link sublink' onclick='on_menu_host("${host.name}")'><i class="fa fa-desktop"></i><span>${host.name}</span></a>`;
    });
    document.getElementById("sidebar").innerHTML = mainMenu;
  });
})
