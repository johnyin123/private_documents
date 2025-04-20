const config = { g_hosts: {} };
function genOption(jsonobj, selectedValue = '') {
  return jsonobj.map(item => {
    return `<option value="${item.name}" ${item.name === selectedValue ? 'selected' : ''}>${item.desc}</option>`;
  }).join('');
}
function filterByKey(array, key, value) {
  return array.filter(item => item[key] === value);
}
function getFormJSON(form) {
  const data = new FormData(form);
  return Object.fromEntries(data.entries());
}
function showView(id) {
  const view = document.getElementById(id);
  const tabContents = document.getElementsByClassName('tabContent');
  Array.from(tabContents).forEach(content => content.style.display = 'none');
  if (view) view.style.display = 'block';
}
function genActBtn(smsg, icon, action, ...args) {
  // args must string
  const str_arg = args.length ? `"${args.join('","')}"` : '';
  return `<button title='${smsg}' onclick='${action}(${str_arg})'><i class="fa ${icon}"></i></button>`;
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
          change_media = `<a title="change media" href="javascript:change_iso('${host}', '${item.uuid}', '${disk.dev}')">Change<a>`;
        }
        tbl += host ? `<td><a title="Remove Disk" href="javascript:del_device('${host}', '${item.uuid}', '${disk.dev}')">Remove</a>${change_media}</td></tr>` : `</tr>`;
      });
    } else if (key === 'nets') {
      const nets = JSON.parse(item[key]);
      nets.forEach(net => {
        tbl += `<tr><th>${net.type}</th><td colspan="${colspan}" class="truncate" title="${net.mac}">${net.mac}</td>`;
        tbl += host ? `<td><a title="Remove netcard" href="javascript:del_device('${host}', '${item.uuid}', '${net.mac}')">Remove</a></td></tr>`: `</tr>`;
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
      const index = config.g_hosts.findIndex(element => element.name === item.kvmhost);
      const btn = `<button title='GOTO HOST' onclick='on_menu_host(config.g_hosts, ${index})'><i class="fa fa-cog fa-spin fa-lg"></i></button>`;
      const table = genVmTblItems(item);
      tbl += genWrapper("vms-wrapper", "<h2>GUEST</h2>", btn, table);
    });
    dbvms.innerHTML = tbl;
  });
  showView(view);
}
function show_vms(host, vms) {
  var tbl = '';
  vms.forEach(item => {
    var btn = genActBtn('Show XML', 'fa-file-code-o', 'show_xml', host, item.uuid);
    btn += genActBtn('Guest Admin UI', 'fa-ambulance', 'show_vmui', host, item.uuid);
    if(item.state === 'RUN') {
      btn += genActBtn('VNC View', 'fa-desktop', 'display', host, item.uuid);
      btn += genActBtn('Reset VM', 'fa-refresh', 'reset', host, item.uuid);
      btn += genActBtn('Stop VM', 'fa-power-off', 'stop', host, item.uuid);
      btn += genActBtn('ForceStop VM', 'fa-plug', 'force_stop', host, item.uuid);
    } else {
      btn += genActBtn('Start VM', 'fa-play', 'start', host, item.uuid);
      btn += genActBtn('Undefine', 'fa-trash', 'undefine', host, item.uuid);
    } 
    btn += genActBtn('Add CDROM', 'fa-floppy-o', 'add_cdrom', host, item.uuid);
    btn += genActBtn('Add NET', 'fa-wifi', 'add_net', host, item.uuid);
    btn += genActBtn('Add DISK', 'fa-database', 'add_disk', host, item.uuid);
    const table = genVmTblItems(item, host);
    const title = item.state == "RUN" ?  '<h2 class="running">GUEST</h2>' : '<h2>GUEST</h2>';
    tbl += genWrapper("vms-wrapper", title, btn, table);
  });
  return tbl;
}
function show_host(host) {
  // delete host.last_modified;
  var btn = genActBtn('Refresh VM List', 'fa-refresh fa-spin', 'vmlist', host.name);
  btn += genActBtn('Create VM', 'fa-tasks', 'create_vm', host.name, host.arch);
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
  const timeoutId = setTimeout(() => controller.abort(), timeout);
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
    disperr(999, `local error`, `${e.toString()}, ${res}`);
  }
}
function show_xml(host, uuid) {
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
function show_vmui(host, uuid) {
  const form = document.getElementById('vmui_form');
  form.addEventListener('submit', function(event) {
    showView('vmuimail');
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    const d = Date.parse(`${res.date} ${res.time}`).valueOf();
    const epoch = Math.floor(d / 1000);
    getjson('GET', `/vm/ui/${host}/${uuid}/${epoch}`, function(resp) {
      var result = JSON.parse(resp);
      if(result.result === 'OK') {
        document.getElementById('email').value = '';
        document.getElementById('expire').value = result.expire;
        document.getElementById('token').value = result.token;
        var url = document.getElementById('url');
        url.setAttribute("href", `${result.url}?token=${result.token}`);
        url.innerHTML = `UUID:${uuid}`;
      } else {
        disperr(result.code, result.name, result.desc);
      }
    });
  }, { once: true });
  form.reset();
  showView('vmui');
}
function start(host, uuid) {
  if (confirm(`Start ${uuid}?`)) {
    getjson('GET', `/vm/start/${host}/${uuid}`, getjson_result, null, null, 60000);
  }
}
function reset(host, uuid) {
  if (confirm(`Reset ${uuid}?`)) {
    getjson('GET', `/vm/reset/${host}/${uuid}`, getjson_result);
  }
}
function stop(host, uuid, force=false) {
  if (confirm(`${force ? 'Force ' : ''}Stop ${uuid}?`)) {
    getjson('GET', `/vm/stop/${host}/${uuid}${force ? '?force=true' : ''}`, getjson_result);
  }
}
function force_stop(host, uuid) {
    stop(host, uuid, true);
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
      window.open(result.display, "_blank");
    } else {
      disperr(result.code, result.name, result.desc);
    }
  });
}
function del_device(host, uuid, dev) {
  if (confirm(`delete device /${host}/${uuid}/${dev} ?`)) {
    getjson('POST', `/vm/detach_device/${host}/${uuid}?dev=${dev}`, getjson_result);
  }
}
function change_iso(host, uuid, dev) {
  const isolist = document.getElementById('isoname_list');
  getjson('GET', `/tpl/iso/`, function(resp) {
    var iso = JSON.parse(resp);
    isolist.innerHTML = genOption(iso);
  });
  const form = document.getElementById('changecdrom_form');
  form.addEventListener('submit', function(event) {
    showView('hostlist');
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    getjson('POST', `/vm/cdrom/${host}/${uuid}?dev=${dev}`, getjson_result, res);
  }, { once: true });
  form.reset();
  showView('changecdrom');
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
    getjson('POST', `/vm/create/${host}`, getjson_result, res);
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
    overlay_output.innerHTML += resp; /*overlay_output.innerHTML = resp;*/
    overlay_output.scrollTop=overlay_output.scrollHeight;
  }, 600000); /*add disk 10m timeout*/
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
function add_cdrom(host, uuid) {
  const form = document.getElementById('addcdrom_form');
  const cdromlst = document.getElementById('cdrom_list');
  getjson('GET', `/tpl/device/${host}`, function(resp) {
    var devs = JSON.parse(resp);
    cdromlst.innerHTML = genOption(filterByKey(devs, 'devtype', 'iso'));
  });
  form.addEventListener('submit', function(event) {
    showView('hostlist');
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    do_add(host, uuid, res);
  }, { once: true });
  form.reset();
  showView('addcdrom');
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
  c_name.innerHTML = '<input type="text" maxlength="10" placeholder="name" onChange="set_name(this)" required>';
  c_value.innerHTML = '<input type="text" maxlength="50" placeholder="value" required>';
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
