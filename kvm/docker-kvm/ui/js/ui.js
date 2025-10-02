"use strict";
const uri_pre = '';
const config = { g_host: [], g_device:[], g_iso:[], g_gold:[], curr_host:'', curr_vm:'', curr_dev:'' };
function get_iso() { return config.g_iso; }
function get_gold() { return config.g_gold; }
function curr_host() { return config.curr_host; }
function curr_vm() { return config.curr_vm; }
function curr_dev() { return config.curr_dev; }
function set_curr(kvmhost, uuid=null, dev=null) {
  config.curr_host = kvmhost;
  if(uuid) config.curr_vm = uuid;
  if(dev) config.curr_dev = dev;
  // console.debug(config.curr_host, config.curr_vm, config.curr_dev);
}
/*deep copy return*/
function getGold(name, arch) { return JSON.parse(JSON.stringify(config.g_gold.find(el => el.name === name && el.arch  === arch))); }
function getIso(name) { return JSON.parse(JSON.stringify(config.g_iso.find(el => el.name === name))); }
function getHost(kvmhost) { return JSON.parse(JSON.stringify(config.g_host.find(el => el.name === kvmhost))); }
function getDevice(kvmhost) { return filterByKey(config.g_device, 'kvmhost', kvmhost); }
function genOption(jsonobj, selectedValue = '', ext1 = null, ext2 = null) {
  return jsonobj.map(item => {
    let data_ext1 = ext1 ? `data-ext1="${item[ext1]}"` : "";
    let data_ext2 = ext2 ? `data-ext2="${item[ext2]}"` : "";
    return `<option ${data_ext1} ${data_ext2} value="${item.name}" ${item.desc === selectedValue ? 'selected' : ''}>${item.desc}</option>`;
  }).join('');
}
function filterByKey(array, key, value) {
  return array.filter(item => item[key] === value);
}
function getFormJSON(form, reset=true) {
  const data = new FormData(form);
  if(reset == true) { form.reset(); }
  const checkboxes = form.querySelectorAll('input[type="checkbox"]');
  checkboxes.forEach(checkbox => {
    if (!data.has(checkbox.name)) {
      data.append(checkbox.name, 'n/a');
    }
  });
  return Object.fromEntries(data.entries());
}
function decodeURLSafeBase64(encodedString) {
  let base64 = encodedString.replace(/-/g, '+').replace(/_/g, '/');
  while (base64.length % 4) {
    base64 += '=';
  }
  return atob(base64);
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
    //return `<button title='${smsg}' onclick='${action}(${str_arg})'><i class="fa ${icon}"></i></button>`;
    return `<button class="iconbtn" style="--icon:var(--${icon});" title='${smsg}' onclick='${action}(${str_arg})'></button>`;
  }
  return `<a title='${smsg}' href='#' onclick='${action}(${str_arg},this)'>${icon}</a>`;
}
function genWrapper(clazz, title, buttons, table) {
  return `<div class="${clazz}"><div class="${clazz}-header">${title}<div>${buttons}</div></div>${table}</div>`;
}
function genVmsTBL(item, host = null) {
  const colspan= host ? 2 : 3;
  var tbl = '<table>';
  for(const key in item) {
    if(key === 'disks') {
      const disks = item[key];
      disks.forEach(disk => {
        tbl += `<tr><th class="truncate" title="${disk.device}">${disk.bus}:${disk.dev}</th><td colspan="${colspan}" class="truncate" title="${disk.vol}">${disk.type}:${disk.vol}</td>`;
        var addon_btn = '';
        if(disk.device === 'cdrom') {
          addon_btn = genActBtn(false, 'Change ISO', 'Change', 'change_iso', host, {'uuid':item.uuid, 'dev':disk.dev});
        }
        if(disk.device === 'disk') {
          addon_btn = genActBtn(false, 'Disk Size', 'DiskSize', 'disk_size', host, {'uuid':item.uuid, 'dev':disk.dev});
        }
        var remove_btn = genActBtn(false, `Remove ${disk.device}`, 'Remove', 'del_device', host, {'uuid':item.uuid, 'dev':disk.dev});
        tbl += host ? `<td><div class="flex-group">${remove_btn}${addon_btn}</div></td></tr>` : `</tr>`;
      });
    } else if (key === 'nets') {
      const nets = item[key];
      nets.forEach(net => {
        tbl += `<tr><th class="truncate">${net.model}:${net.type}</th><td colspan="${colspan}" class="truncate" title="${net.mac}">${net.mac}</td>`;
        var btn = genActBtn(false, 'Remove netcard', 'Remove', 'del_device', host, {'uuid':item.uuid, 'dev':net.mac});
        if (item['state'] === 'RUN') {
            btn += genActBtn(false, 'Net Stats', 'NetStats', 'netstats', host, {'uuid':item.uuid, 'dev':net.mac});
        }
        tbl += host ? `<td><div class="flex-group">${btn}</div></td></tr>`: `</tr>`;
      });
    } else if (key === 'mdconfig') {
      const mdconfig = item[key];
      for(var mdkey in mdconfig) {
        tbl += `<tr><th class="truncate" title="mdconfig ${mdkey}">${mdkey}#</th><td colspan="${colspan}" class="truncate">${mdconfig[mdkey]}</td>`;
        var btn = genActBtn(false, 'Modify mdconfig', 'Modify', 'modify_mdconfig', host, {'uuid':item.uuid,'key':mdkey});
        tbl += host ? `<td><div class="flex-group">${btn}</div></td></tr>`: `</tr>`;
      }
    } else if (key === 'uuid' && host) {
      var btn = genActBtn(false, 'List Snapshot', 'Snapshots', 'snap_list', host, {'uuid':item.uuid});
      tbl += `<tr><th class="truncate">${key}</th><td colspan="${colspan}" class="truncate">${item[key]}</td><td>${btn}</td></tr>`;
    } else if (key === 'curcpu' && host) {
      var btn = genActBtn(false, 'Modify Vcpus', 'Modify', 'modify_vcpus', host, {'uuid':item.uuid});
      tbl += `<tr><th class="truncate">${key}</th><td colspan="${colspan}" class="truncate">${item[key]}</td><td>${btn}</td></tr>`;
    } else if (key === 'curmem' && host) {
      var btn = genActBtn(false, 'Modify Memory', 'Modify', 'modify_memory', host, {'uuid':item.uuid});
      tbl += `<tr><th class="truncate">${key}</th><td colspan="${colspan}" class="truncate">${item[key]}</td><td>${btn}</td></tr>`;
    } else if (key === 'desc' && host) {
      var btn = genActBtn(false, 'Modify Description', 'Modify', 'modify_desc', host, {'uuid':item.uuid});
      tbl += `<tr><th class="truncate">${key}</th><td colspan="${colspan}" class="truncate">${item[key]}</td><td>${btn}</td></tr>`;
    } else if (key === 'state' && item['state'] === 'RUN' && host) {
      var btn = genActBtn(false, 'VM IPAddress', 'VMIPaddr', 'get_vmip', host, {'uuid':item.uuid});
      tbl += `<tr><th class="truncate">${key}</th><td colspan="${colspan}" class="truncate">${item[key]}</td><td>${btn}</td></tr>`;
    } else {
      var style = 'truncate';
      if (item.uuid === curr_vm() && ['uuid'].includes(key)) style +=' blue';
      tbl += `<tr><th class="${style}">${key}</th><td colspan="3" class="${style}">${item[key]}</td></tr>`;
    }
  }
  tbl += '</table>';
  return tbl;
}
function manage_vm(kvmhost, uuid) {
  set_curr(kvmhost, uuid);
  flush_sidebar(kvmhost);
  document.getElementById("snap_info").innerHTML = '';
  showView("manage_vm");
  getjson('GET', `${uri_pre}/vm/list/${kvmhost}/${uuid}`, function(resp){
    const result = JSON.parse(resp);
    var btn = genActBtn(true, 'Show XML', 'fa-commenting', 'show_xml', kvmhost, {'uuid':result.guest.uuid});
    btn += genActBtn(true, 'Control Panel', 'fa-share-alt', 'show_vmui', kvmhost, {'uuid':result.guest.uuid});
    if(result.guest.state === 'RUN') {
      btn += genActBtn(true, 'Console', 'fa-wrench', 'ttyconsole', kvmhost, {'uuid':result.guest.uuid});
      btn += genActBtn(true, 'Display View', 'fa-desktop', 'display', kvmhost, {'uuid':result.guest.uuid});
      btn += genActBtn(true, 'Reset VM', 'fa-registered', 'reset', kvmhost, {'uuid':result.guest.uuid});
      btn += genActBtn(true, 'Stop VM', 'fa-power-off', 'stop', kvmhost, {'uuid':result.guest.uuid});
      btn += genActBtn(true, 'ForceStop VM', 'fa-plug', 'force_stop', kvmhost, {'uuid':result.guest.uuid});
    } else {
      btn += genActBtn(true, 'Start VM', 'fa-play-circle', 'start', kvmhost, {'uuid':result.guest.uuid});
      btn += genActBtn(true, 'Undefine', 'fa-recycle', 'undefine', kvmhost, {'uuid':result.guest.uuid});
    }
    btn += genActBtn(true, 'Add CDROM', 'fa-folder-open' , 'add_cdrom', kvmhost, {'uuid':result.guest.uuid});
    btn += genActBtn(true, 'Add NET', 'fa-sitemap', 'add_net', kvmhost, {'uuid':result.guest.uuid});
    btn += genActBtn(true, 'Add DISK', 'fa-database', 'add_disk', kvmhost, {'uuid':result.guest.uuid});
    btn += genActBtn(true, 'Refresh VM', 'fa-refresh', 'manage_vm', kvmhost, {'uuid':result.guest.uuid});
    btn += `<button title="Close" onclick="vmlist('${kvmhost}');">&times;</button>`;
    const table = genVmsTBL(result.guest, kvmhost);
    const title = result.guest.state == "RUN" ? `<h2 class="green">GUEST</h2>` : `<h2>GUEST</h2>`;
    const tbl = genWrapper("vms-wrapper", title, btn, table);
    document.getElementById("vm_info").innerHTML = tbl;
  });
}
function show_vms(kvmhost, vms) {
  var tbl = '';
  vms.forEach(item => {
    const table = genVmsTBL(item);
    var btn = genActBtn(true, 'Show XML', 'fa-commenting', 'show_xml', kvmhost, {'uuid':item.uuid});
    if (item.state === "RUN") {
      btn += genActBtn(true, 'VM IPAddress', 'fa-at', 'get_vmip', kvmhost, {'uuid':item.uuid});
    } else {
      btn += genActBtn(true, 'Start VM', 'fa-play-circle', 'start', kvmhost, {'uuid':item.uuid, 'backlist':'1'});
      btn += genActBtn(true, 'Undefine', 'fa-recycle', 'undefine', kvmhost, {'uuid':item.uuid});
    }
    btn += genActBtn(true, 'Manage VM', 'fa-ellipsis-h', 'manage_vm', kvmhost, {'uuid':item.uuid});
    const title = item.state == "RUN" ? '<h2 class="green">GUEST</h2>' : '<h2>GUEST</h2>';
    tbl += genWrapper("vms-wrapper", title, btn, table);
  });
  return tbl;
}
function show_host(kvmhost, more_info) {
  var host = getHost(kvmhost);
  delete host.vars;
  var btn = genActBtn(true, 'Refresh VM List', 'fa-refresh', 'vmlist', host.name);
  btn += genActBtn(true, 'Create VM', 'fa-plus-circle', 'create_vm', host.name);
  const table = genVmsTBL(Object.assign({}, host, more_info));
  return genWrapper('host-wrapper', `<h2 class="green">${host.name.toUpperCase()}</h2>`, btn, table);
}
function Alert(type, title, message) {
  const div_alert = document.getElementById("alert");
  function closeDialogOnClickOutside(event) {
    event.target === div_alert && closeDialog();
  }
  function closeDialog() {
    div_alert.close();
    div_alert.removeEventListener("click", closeDialogOnClickOutside);
  }
  if (div_alert) {
    const btn = `<button title="Close" onclick="this.closest('dialog').close();">&times;</button>`;
    const table = `<form><pre style="white-space: pre-wrap;">${message}</pre></form>`;
    div_alert.innerHTML = genWrapper('form-wrapper', `<h2 class="${type}">${title}</h2>`, btn, table);
    div_alert.showModal();
    div_alert.addEventListener("click", closeDialogOnClickOutside);
  } else {
    alert(`${type}-${title}:${message}`);
  }
}
function dispok(desc) { Alert('success', 'SUCCESS', desc); }
function disperr(code, name, desc) { Alert('error', `${name}: ${code}`, desc); }
function toggleOverlay(visible) {
  const overlay = document.getElementById("overlay");
  if (overlay) {
    overlay.style.display = visible ? "block" : "none";
    if (visible) {
      document.querySelector("#overlay_output").innerHTML = "";
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
  fetch(url, opts).then(response => {
    if (!response.ok) {
      return response.text().then(text => { throw new Error(text); });
    }
    if(stream && typeof(stream) == "function") {
      const reader = response.clone().body.getReader();
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
function processJsonArray(jsonArray) {
  const counts = new Map();
  jsonArray.forEach(obj => {
    const key = JSON.stringify(obj); // Stringify to compare objects
    counts.set(key, (counts.get(key) || 0) + 1);
  });
  const result = jsonArray.map(obj => {
    const key = JSON.stringify(obj);
    return { ...obj, vms: counts.get(key) };
  });
  const uniqueResult = Array.from(new Set(result.map(JSON.stringify))).map(JSON.parse);
  return uniqueResult;
}
function flush_sidebar(kvmhost, count=null) {
  document.getElementById("sidebar").querySelectorAll("a").forEach(link => {
    link.classList.remove('blue');
    if(link.querySelector('[name="host"]').innerHTML === kvmhost) {
      link.classList.add('blue');
      if(count) link.querySelector(`[name="count"]`).innerHTML = count;
    }
  });
}
function vmlist(kvmhost) {
  document.getElementById("vms").innerHTML = '';
  document.getElementById("host").innerHTML = '';
  var url = `${uri_pre}/vm/list/`;
  if(kvmhost !== 'ALL VMS') {
    url += kvmhost;
    set_curr(kvmhost);
  }
  getjson('GET', url, function(resp) {
    const result = JSON.parse(resp);
    if(result.result !== 'OK') { Alert('error', 'vmlist', 'Get VM List'); return; };
    const guest = result.guest;
    if(kvmhost === 'ALL VMS') {
      var tbl = '';
      var count = 0;
      guest.forEach(item => {
        item.guests.forEach(rec => {
          count ++;
          const btn = `<button class="iconbtn" style="--icon:var(--fa-ellipsis-h);" title='Manage VM' onclick='manage_vm("${item.kvmhost}", "${rec.uuid}")'></button>`;
          rec.kvmhost = item.kvmhost;
          rec.arch = item.arch;
          const table = genVmsTBL(rec);
          tbl += genWrapper("vms-wrapper", "<h2>GUEST</h2>", btn, table);
        });
      });
      flush_sidebar(kvmhost, `(${count})`);
      document.getElementById("vms").innerHTML = tbl;
      const newArray = guest.map(item => {
        const { kvmhost, arch } = item;
        return { kvmhost, arch };
      });
      tbl = '<table>';
      processJsonArray(newArray).forEach(item => {
        tbl += `<tr><th title='host arch'>${item.arch}</th><td title='total vms'>${item.vms}</td><td><a href='#' title='Manage Host' onclick='vmlist("${item.kvmhost}")'>${item.kvmhost}</a></td></tr>`;
      });
      tbl += '</table>';
      document.getElementById("host").innerHTML = genWrapper('host-wrapper', `<h2 class="green">Summary</h2>`, '', tbl);
    } else {
      flush_sidebar(kvmhost, `(${result.host.active}/${result.host.totalvm})`);
      document.getElementById("vms").innerHTML = show_vms(kvmhost, result.guest);
      document.getElementById("host").innerHTML = show_host(kvmhost, result.host);
    }
    showView("hostlist");
  });
}
function getjson_result(res) {
  try {
    var result = JSON.parse(res);
    if(result.result === 'OK') {
      var desc = result.desc;
      delete result.result;
      delete result.desc;
      if (result.uuid?.length > 0) {
        // Key exists and has a value
        set_curr(curr_host(), result.uuid);
      } else {
        set_curr(curr_host(), '');
      }
      if (Object.keys(result).length === 0) {
        dispok(`${desc}`);
      } else {
        dispok(`${desc} ${JSON.stringify(result)}`);
      }
      return true;
    } else {
      disperr(result.code, result.name, result.desc);
    }
  } catch (e) {
    disperr(666, `local error`, `${e.toString()}, ${res}`);
  }
  return false;
}
function show_xml(host, uuid) {
  set_curr(host, uuid);
  getjson('GET', `${uri_pre}/vm/xml/${host}/${uuid}`, function(resp) {
    var result = JSON.parse(resp);
    if(result.result === 'OK') {
      Alert('success', `XMLDesc`, result.xml.replace(/</g, "&lt;").replace(/>/g, "&gt;"));
    } else {
      disperr(result.code, result.name, result.desc);
    }
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
  const epoch = Math.floor(Date.parse(`${res.date} 23:59:59`).valueOf() / 1000);
  getjson('GET', `${uri_pre}/vm/ui/${curr_host()}/${curr_vm()}?epoch=${epoch}`, function(resp) {
    var result = JSON.parse(resp);
    if(result.result === 'OK') {
      document.getElementById('email').value = '';
      document.getElementById('expire').value = result.expire;
      document.getElementById('token').value = result.token;
      var url = document.getElementById('url');
      url.setAttribute("href", `${result.url}?token=${result.token}`);
      url.innerHTML = `${curr_vm()}`;
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
function start(host, uuid, backlist = null) {
  set_curr(host, uuid);
  if (confirm(`Start ${uuid}?`)) {
    getjson('GET', `${uri_pre}/vm/start/${host}/${uuid}`, function(resp) {
      getjson_result(resp);
      if (backlist) {
        vmlist(host);
      } else {
        manage_vm(host, uuid);
      }
    });
  }
}
function reset(host, uuid) {
  set_curr(host, uuid);
  if (confirm(`Reset ${uuid}?`)) {
    getjson('GET', `${uri_pre}/vm/reset/${host}/${uuid}`, getjson_result);
  }
}
function stop(host, uuid, force=false) {
  set_curr(host, uuid);
  if (confirm(`${force ? 'Force ' : ''}Stop ${uuid}?`)) {
    getjson('GET', `${uri_pre}/vm/stop/${host}/${uuid}${force ? '?force=true' : ''}`, function(resp) {
      getjson_result(resp);
      manage_vm(curr_host(), curr_vm());
    });
  }
}
function force_stop(host, uuid) {
  stop(host, uuid, true);
}
function undefine(host, uuid) {
  set_curr(host, uuid);
  if (confirm(`Undefine ${uuid}?`)) {
    getjson('GET', `${uri_pre}/vm/delete/${host}/${uuid}`, function(resp){ getjson_result(resp); vmlist(host); });
  }
}
function display(host, uuid, disp='') {
  set_curr(host, uuid);
  getjson('GET', `${uri_pre}/vm/display/${host}/${uuid}?disp=${disp}`, function(resp) {
    var result = JSON.parse(resp);
    if(result.result === 'OK') {
      //document.getElementById("display").src = result.display;
      var parm=encodeURIComponent(`${decodeURLSafeBase64(result.access)}&token=${result.token}&disp=${result.disp}&expire=${result.expire}`);
      window.open(`${uri_pre}${result.display}/${parm}`, "_blank");
    } else {
      disperr(result.code, result.name, result.desc);
    }
  });
}
function ttyconsole(host, uuid) { display(host, uuid, 'console'); }
function get_vmip(host, uuid, btn = null) {
  set_curr(host, uuid);
  getjson('GET', `${uri_pre}/vm/ipaddr/${host}/${uuid}`, getjson_result);
}
function del_device(host, uuid, dev, btn) {
  set_curr(host, uuid, dev);
  if (confirm(`delete device /${host}/${uuid}/${dev} ?`)) {
    getjson('POST', `${uri_pre}/vm/detach_device/${host}/${uuid}?dev=${dev}`, function(resp) {
      getjson_result(resp);
      manage_vm(curr_host(), curr_vm());
    });
  }
}
function on_changeiso(form) {
  getjson('POST', `${uri_pre}/vm/cdrom/${curr_host()}/${curr_vm()}?dev=${curr_dev()}`,function(resp) {
      getjson_result(resp);
      manage_vm(curr_host(), curr_vm());
    }, getFormJSON(form));
  return false;
}
function disk_size(host, uuid, dev, btn) {
  set_curr(host, uuid, dev);
  getjson('GET', `${uri_pre}/vm/blksize/${curr_host()}/${curr_vm()}?dev=${dev}`, function(resp){
    if (getjson_result(resp)) {
      const result = JSON.parse(resp);
      const row = btn.closest('tr');
      const cells = row.cells;
      cells[0].innerText = `${dev}(${result.size})`;
      btn.setAttribute("hidden", "");
    }
  });
}
function change_iso(host, uuid, dev, btn) {
  set_curr(host, uuid, dev);
  showView('changecdrom');
  document.getElementById('isoname_list').innerHTML = genOption(get_iso());
}
function on_createvm(form) {
  getjson('POST', `${uri_pre}/vm/create/${curr_host()}`, function(resp){
    if (getjson_result(resp)) {
        manage_vm(curr_host(), curr_vm());
    }
  }, getFormJSON(form));
  return false;
}
function cpWithoutKeys(orig, keys) {
  const newvars = {};
  for (const key in orig) {
    if (!keys.includes(key)) {
      newvars[key] = orig[key];
    }
  }
  return newvars;
}
function create_vm(host) {
  set_curr(host, '');
  showView('createvm');
  const form = document.getElementById("createvm_form");
  form.querySelector(`table[name="meta_data"]`).innerHTML = '';
  const objs = Object.keys(getFormJSON(form, false));
  set_help(form, cpWithoutKeys(getHost(host).vars, objs));
}
function on_add(form) {
  function getLastLine(str) {
    const lines = str.split('\n');
    return lines[lines.length - 1];
  }
  var res = getFormJSON(form);
  const device = res.device;
  delete res.device;
  getjson('POST', `${uri_pre}/vm/attach_device/${curr_host()}/${curr_vm()}?dev=${device}`, function(resp) {
    getjson_result(getLastLine(resp));
    manage_vm(curr_host(), curr_vm());
  }, res, function(resp) {
    const overlay_output = document.querySelector("#overlay_output");
    overlay_output.innerHTML += resp; /*overlay_output.innerHTML = resp;*/
    overlay_output.scrollTop=overlay_output.scrollHeight;
  }, 600000); /*add disk 10m timeout*/
  return false;
}
function gold_change(e) {
  const input = document.getElementById("gold_size");
  input.value = Math.ceil(e.options[e.selectedIndex].getAttribute("data-ext1")/1024/1024/1024);
  input.setAttribute('min', input.value);
}
function add_disk(host, uuid) {
  set_curr(host, uuid);
  showView('adddisk');
  const form = document.getElementById("adddisk_form");
  form.querySelector(`table[name="meta_data"]`).innerHTML = '';
  const disks = filterByKey(getDevice(host), 'devtype', 'disk');
  const objs = Object.keys(getFormJSON(form, false));
  if(disks.length > 0) {
    // no disk device of this host found
    set_help(form, cpWithoutKeys(disks[0]['vars'], objs));
  }
  document.getElementById('dev_list').innerHTML = genOption(disks);
  const gold = filterByKey(get_gold(), 'arch', getHost(host).arch);
  const gold_list = document.getElementById('gold_list');
  gold_list.innerHTML = genOption(gold, '数据盘', 'size');
  const input = document.getElementById("gold_size");
  input.value = Math.ceil(gold_list.options[gold_list.selectedIndex].getAttribute("data-ext1")/1024/1024/1024);
  input.setAttribute('min', input.value);
}
function add_net(host, uuid) {
  set_curr(host, uuid);
  showView('addnet');
  const form = document.getElementById("addnet_form");
  form.querySelector(`table[name="meta_data"]`).innerHTML = '';
  const nets = filterByKey(getDevice(host), 'devtype', 'net');
  const objs = Object.keys(getFormJSON(form, false));
  if(nets.length > 0) { set_help(form, cpWithoutKeys(nets[0]['vars'], objs)); }
  document.getElementById('net_list').innerHTML = genOption(nets);
}
function add_cdrom(host, uuid) {
  set_curr(host, uuid);
  showView('addcdrom');
  const form = document.getElementById("addcdrom_form");
  form.querySelector(`table[name="meta_data"]`).innerHTML = '';
  const cdroms = filterByKey(getDevice(host), 'devtype', 'cdrom');
  const objs = Object.keys(getFormJSON(form, false));
  if(cdroms.length > 0) { set_help(form, cpWithoutKeys(cdroms[0]['vars'], objs)); }
  document.getElementById('cdrom_list').innerHTML = genOption(cdroms);
}
function on_modifydesc(form) {
  const res = getFormJSON(form);
  getjson('GET', `${uri_pre}/vm/desc/${curr_host()}/${curr_vm()}?vm_desc=${res.vm_desc}`, function(resp) {
    getjson_result(resp);
    manage_vm(curr_host(), curr_vm());
  });
  return false;
}
function modify_desc(host, uuid, btn) {
  set_curr(host, uuid);
  showView('modifydesc');
}
function on_modifymemory(form) {
  const res = getFormJSON(form);
  getjson('GET', `${uri_pre}/vm/setmem/${curr_host()}/${curr_vm()}?vm_ram_mb=${res.vm_ram_mb}`,function(resp) {
    getjson_result(resp);
    manage_vm(curr_host(), curr_vm());
  });
  return false;
}
function modify_memory(host, uuid, btn) {
  set_curr(host, uuid);
  showView('modifymemory');
}
function on_modifyvcpus(form) {
  const res = getFormJSON(form);
  getjson('GET', `${uri_pre}/vm/setcpu/${curr_host()}/${curr_vm()}?vm_vcpus=${res.vm_vcpus}`,function(resp) {
    getjson_result(resp);
    manage_vm(curr_host(), curr_vm());
  });
  return false;
}
function on_modifymdconfig(form) {
  const res = getFormJSON(form);
  getjson('POST', `${uri_pre}/vm/metadata/${curr_host()}/${curr_vm()}`,function(resp) {
    getjson_result(resp);
    manage_vm(curr_host(), curr_vm());
  }, res);
  return false;
}
function on_addiso(form) {
  if (confirm(`Are you sure add iso?`)) {
    const res = getFormJSON(form, false);
    getjson('POST', `${uri_pre}/conf/iso/`,function(resp) {
      if (getjson_result(resp)) { form.reset(); }
    }, res);
  }
  return false;
}
function on_addgold(form) {
  if (confirm(`Are you sure add gold?`)) {
    const res = getFormJSON(form, false);
    getjson('POST', `${uri_pre}/conf/gold/`,function(resp) {
      if (getjson_result(resp)) { form.reset(); }
    }, res);
  }
  return false;
}
function on_addhost(form) {
  if (confirm(`Are you sure add kvmhost?`)) {
    const res = getFormJSON(form, false);
    getjson('POST', `${uri_pre}/conf/host/`,function(resp) {
      if (getjson_result(resp)) { form.reset(); }
    }, res);
  }
  return false;
}
function conf_backup(btn) {
  if (confirm(`Are you sure download config backup file ?`)) {
    window.open(`/conf/backup/`, "_blank");
  }
}
function set_form_inputs(myform, inputs, chkboxes) {
  const formElements = myform.elements;
  for (let i = 0; i < formElements.length; i++) {
    const elem = formElements[i];
    if (elem.tagName === 'INPUT') {
      if (elem.type === 'checkbox') {
        elem.checked = false;
      }
    }
  }
  for(const key of chkboxes) {
    const elem =  myform.elements[key.name];
    if (elem === undefined) {
      console.error('input:', key, elem);
      continue;
    }
    if (elem.type === 'checkbox') {
      elem.checked = true;
    }
   }
  for(const key in inputs) {
    const elem =  myform.elements[key];
    if (elem === undefined) {
      console.error('input:', key, elem);
      continue;
    }
    elem.value  = inputs[key];
  }

}
function edit_cfg_host(host, form, btn) {
  var kvmhost = getHost(host);
  delete kvmhost.vars;
  const devices = getDevice(host);
  const myform = document.getElementById(form);
  set_form_inputs(myform, kvmhost, devices);
}
function delete_cfg_host(host, btn) {
  if (confirm(`Are you sure delete ${host}?`)) {
    getjson('DELETE', `${uri_pre}/conf/host/?name=${host}`, getjson_result);
  }
}
function on_cfg_list_host(btn) {
  const div = document.getElementById('conf_host_list');
  getjson('GET', `${uri_pre}/tpl/host/?${Date.now()}`, function (resp) {
    const res = JSON.parse(resp);
    if(res.result !== 'OK') { Alert('error', 'conf', 'Get Host List'); return; };
    config.g_host = res.host;
    gen_sidebar();
    flush_sidebar("CONFIG");
    getjson('GET', `${uri_pre}/tpl/device/?${Date.now()}`, function(resp) {
      const res = JSON.parse(resp);
      if(res.result !== 'OK') { Alert('error', 'init', 'Get Device List'); return; };
      config.g_device = res.device;
      var tbl = `<table><tr><th class="truncate">Name</th><th class="truncate">Arch</th><th class="truncate">IPADDR</th><th class="truncate">DEVS</th><th>ACT</th></tr>`;
      config.g_host.forEach(host => {
        var btn = genActBtn(false, 'Edit', 'Edit', 'edit_cfg_host', host.name, {'form':'addhost_form'}) + genActBtn(false, 'Delete', 'Delete', 'delete_cfg_host', host.name);
        var devs = getDevice(host.name).map(dev => dev.name);
        tbl += `<tr><td>${host.name}</td><td class="truncate">${host.arch}</td class="truncate"><td class="truncate">${host.ipaddr}</td><td class="truncate">${devs}</td><td><div class="flex-group">${btn}</div></td></tr>`;
      });
      tbl += '</table>';
      div.innerHTML = tbl;
    });
  });
}
function edit_cfg_gold(name, arch, form, btn) {
  var gold = getGold(name, arch);
  gold.size = Math.trunc(gold.size / (1024 ** 3));
  const myform = document.getElementById(form);
  set_form_inputs(myform, gold, []);
}
function delete_cfg_gold(name, arch, btn) {
  if (confirm(`Are you sure delete ${name} ${arch}?`)) {
    getjson('DELETE', `${uri_pre}/conf/gold/?name=${name}&arch=${arch}`, getjson_result);
  }
}
function on_cfg_list_gold(btn) {
  const div = document.getElementById('conf_gold_list');
  getjson('GET', `${uri_pre}/tpl/gold/?${Date.now()}`, function(resp) {
    const res = JSON.parse(resp);
    if(res.result !== 'OK') { Alert('error', 'init', 'Get Gold List'); return; };
    config.g_gold = res.gold;
    var tbl = `<table><tr><th class="truncate">Name</th><th class="truncate">Arch</th><th class="truncate">Size</th><th class="truncate">Desc</th><th>ACT</th></tr>`;
    res.gold.sort((a, b) => a.name.localeCompare(b.name)).forEach(gold => {
      var btn = genActBtn(false, 'Edit', 'Edit', 'edit_cfg_gold', gold.name, {'arch':gold.arch, 'form':'addgold_form'}) + genActBtn(false, 'Delete', 'Delete', 'delete_cfg_gold', gold.name, {'arch':gold.arch});
      tbl += `<tr><td>${gold.name}</td><td class="truncate">${gold.arch}</td class="truncate"><td class="truncate">${gold.size}</td><td class="truncate">${gold.desc}</td><td><div class="flex-group">${btn}</div></td></tr>`;
    });
    tbl += '</table>';
    div.innerHTML = tbl;
  });
}
function edit_cfg_iso(name, form, btn) {
  var iso = getIso(name);
  const myform = document.getElementById(form);
  set_form_inputs(myform, iso, []);
}
function delete_cfg_iso(name, btn) {
  if (confirm(`Are you sure delete ${name}?`)) {
    getjson('DELETE', `${uri_pre}/conf/iso/?name=${name}`, getjson_result);
  }
}
function on_cfg_list_iso(btn) {
  const div = document.getElementById('conf_iso_list');
  getjson('GET', `${uri_pre}/tpl/iso/?${Date.now()}`, function(resp) {
    const res = JSON.parse(resp);
    if(res.result !== 'OK') { Alert('error', 'init', 'Get ISO List'); return; };
    config.g_iso = res.iso;
    var tbl = `<table><tr><th class="truncate">Name</th><th class="truncate">Desc</th><th>ACT</th></tr>`;
    res.iso.forEach(iso => {
      var btn = genActBtn(false, 'Edit', 'Edit', 'edit_cfg_iso', iso.name, {'form':'addiso_form'}) + genActBtn(false, 'Delete', 'Delete', 'delete_cfg_iso', iso.name);
      tbl += `<tr><td>${iso.name}</td><td class="truncate">${iso.desc}</td><td><div class="flex-group">${btn}</div></td></tr>`;
    });
    tbl += '</table>';
    div.innerHTML = tbl;
  });
}
function menu_config(spanval) {
  set_curr(null);
  getjson('GET', `${uri_pre}/conf/domains/`, function(resp) {
    const result = JSON.parse(resp);
    const sel = document.getElementById('conf_domains_tpl');
    sel.innerHTML = '';
    result.domains.forEach(tpl => { sel.innerHTML += `<option value="${tpl}">${tpl}</option>`; });
    getjson('GET', `${uri_pre}/conf/devices/`, function(resp) {
      const result = JSON.parse(resp);
      const div = document.getElementById('conf_devices_tpl');
      div.innerHTML = '';
      result.devices.forEach(tpl => { div.innerHTML += `<label style="font-weight: normal;"><input type="checkbox" name="${tpl}" value="on"/>${tpl}</label>`; });
      showView("configuration");
      flush_sidebar(spanval);
    });
  });
}
function snap_create(host, uuid, btn) {
  if (confirm(`Create snapshot /${host}/${uuid} ?`)) {
    getjson('POST', `${uri_pre}/vm/snapshot/${host}/${uuid}`, function(resp) {
      getjson_result(resp);
      snap_list(host, uuid, btn);
    });
  }
}
function snap_delete(host, uuid, name, btn) {
  if (confirm(`Delete snapshot /${host}/${uuid}/${name} ?`)) {
    getjson('GET', `${uri_pre}/vm/delete_snapshot/${host}/${uuid}?name=${name}`, function(resp) {
      getjson_result(resp);
      snap_list(host, uuid, btn);
    });
  }
}
function snap_revert(host, uuid, name, btn) {
  if (confirm(`Revert snapshot /${host}/${uuid}/${name} ?`)) {
    getjson('GET', `${uri_pre}/vm/revert_snapshot/${host}/${uuid}?name=${name}`, function(resp) {
      getjson_result(resp);
      snap_list(host, uuid, btn);
    });
  }
}
function snap_list(host, uuid, btn) {
  set_curr(host, uuid);
  getjson('GET', `${uri_pre}/vm/snapshot/${host}/${uuid}`, function(resp) {
    var result = JSON.parse(resp);
    if(result.result === 'OK') {
      var tbl = '<table>';
      var btn = genActBtn(false, 'Create Snapshot', 'Create', 'snap_create', host, {'uuid':uuid});
      tbl += `<tr><th class="truncate">Total</th><td class="truncate">${result.num}</td><td><div class="flex-group">${btn}</div></td></tr>`;
      result.names.forEach(name => {
          btn = genActBtn(false, 'Revert Snapshot', 'Revert', 'snap_revert', host, {'uuid':uuid, 'name':name}) + genActBtn(false, 'Delete Snapshot', 'Delete', 'snap_delete', host, {'uuid':uuid, 'name':name});
          tbl += `<tr><th>${name == result.current ? 'Current' : ''}</th><td class="truncate">${name}</td><td><div class="flex-group">${btn}</div></td></tr>`;
      });
      tbl += '</table>';
      document.getElementById("snap_info").innerHTML = genWrapper("vms-wrapper", "<h2>SNAPSHOT</h2>", "", tbl);
    } else {
      disperr(result.code, result.name, result.desc);
    }
  });
}
function modify_vcpus(host, uuid, btn) {
  set_curr(host, uuid);
  showView('modifyvcpus');
}
function modify_mdconfig(host, uuid, key, btn) {
  set_curr(host, uuid);
  const div = document.getElementById('div-metadata');
  div.innerHTML = `<label>${key}:<input type="text" name="${key}"/></label>`;
  showView('modifymdconfig');
}
function netstats(host, uuid, dev, btn) {
  set_curr(host, uuid, dev);
  getjson('GET', `${uri_pre}/vm/netstat/${curr_host()}/${curr_vm()}?dev=${dev}`, getjson_result);
}
/* create vm add new meta key/value */
function set_name(r) {
  const form = r.form;
  const table = form.querySelector(`table[name="meta_data"]`);
  var i = r.parentNode.parentNode.rowIndex;
  var input = table.rows[i].cells[1].getElementsByTagName('input');
  input[0].name=r.value;
}
function del_meta(r) {
  const form = r.form;
  const table = form.querySelector(`table[name="meta_data"]`);
  table.deleteRow(r.parentNode.parentNode.rowIndex);
}
function add_meta(btn) {
  const form = btn.form; //btn.closest('form')
  const table = form.querySelector(`table[name="meta_data"]`);
  const dlist = form.querySelector(`datalist[name="help"]`).id;
  var newRow = table.insertRow(-1);
  var c_name = newRow.insertCell(0);
  var c_value = newRow.insertCell(1);
  var del_btn = newRow.insertCell(2);
  c_name.innerHTML = `<input type="text" maxlength="40" placeholder="name" onChange="set_name(this)" list="${dlist}" autocomplete="off" required>`;
  c_value.innerHTML = '<input type="text" maxlength="200" placeholder="value" required>';
  del_btn.innerHTML = `<input type="button" value="Remove" onclick="del_meta(this)"/>`;
}
function set_help(form, vars) {
  const div = form.querySelector(`div[name="help"]`);
  const dlist = form.querySelector(`datalist[name="help"]`)
  var help_msg = '<details><summary>Fields Info</summary><table>';
  dlist.innerHTML = '';
  for(const key in vars) {
    help_msg += `<tr><th>${key}</th><td colspan=3 class="truncate">${vars[key]}</td></tr>`;
    dlist.innerHTML += `<option value="${key}">`;
  }
  help_msg += `</table></details>`;
  div.innerHTML = help_msg;
}
function select_change(selectObject) {
  const dev = filterByKey(getDevice(curr_host()), 'name', selectObject.value)[0];
  const objs = Object.keys(getFormJSON(selectObject.form, false));
  set_help(selectObject.form, cpWithoutKeys(dev['vars'], objs));
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
function gen_sidebar() {
    var mainMenu =`<a href='#' onclick='menu_config("CONFIG")' class="iconbtn" style="--icon:var(--fa-cog);"><span name='host'>CONFIG</span></a>`;
    mainMenu += `<a href='#' onclick='vmlist("ALL VMS")' class="iconbtn" style="--icon:var(--fa-list-ol);"><span name='host'>ALL VMS</span><span style='float:right;' name='count'></span></a>`;
    config.g_host.forEach(host => {
      mainMenu += `<a href='#' title="${host.arch}" onclick='vmlist("${host.name}")' class="iconbtn" style="--icon:var(--fa-desktop);"><span name='host'>${host.name}</span><span style='float:right;' name='count'></span></a>`;
    });
    document.getElementById("sidebar").innerHTML = mainMenu;
}
/* ------------------------- */
window.addEventListener('load', function() {
  includeHTML();
  getjson('GET', `${uri_pre}/tpl/host/`, function (resp) {
    const result = JSON.parse(resp);
    if(result.result !== 'OK') { Alert('error', 'init', 'Get Host List'); return; }
    config.g_host = result.host;
    gen_sidebar();
  });
  getjson('GET', `${uri_pre}/tpl/iso/`, function(resp) { const result = JSON.parse(resp);if(result.result !== 'OK') { Alert('error', 'init', 'Get ISO List'); return; }; config.g_iso = result.iso; });
  getjson('GET', `${uri_pre}/tpl/gold/`, function(resp) { const result = JSON.parse(resp);if(result.result !== 'OK') { Alert('error', 'init', 'Get Gold List'); return; }; config.g_gold = result.gold; });
  getjson('GET', `${uri_pre}/tpl/device/`, function(resp) { const result = JSON.parse(resp);if(result.result !== 'OK') { Alert('error', 'init', 'Get Device List'); return; }; config.g_device = result.device; });
})
