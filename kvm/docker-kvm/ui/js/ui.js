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
  console.debug(config.curr_host, config.curr_vm, config.curr_dev);
}
/*deep copy return*/
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
  return `<a title='${smsg}' href='#' onclick='${action}(${str_arg})')'>${icon}</a>`;
}
function genWrapper(clazz, title, buttons, table) {
  return `<div class="${clazz}"><div class="${clazz}-header">${title}<div>${buttons}</div></div>${table}</div>`;
}
function genVmsTBL(item, host = null) {
  const colspan= host ? 2 : 3;
  var tbl = '<table>';
  for(const key in item) {
    if(key === 'disks') {
      const disks = JSON.parse(item[key]);
      disks.forEach(disk => {
        tbl += `<tr><th class="truncate" title="${disk.device}">${disk.dev}</th><td colspan="${colspan}" class="truncate" title="${disk.vol}">${disk.type}:${disk.vol}</td>`;
        var addon_btn = '';
        if(disk.device === 'cdrom') {
          addon_btn = genActBtn(false, 'Change Media', 'Change', 'change_iso', host, {'uuid':item.uuid, 'dev':disk.dev});
        }
        if(disk.device === 'disk') {
          addon_btn = genActBtn(false, 'Media Size', 'DiskSize', 'disk_size', host, {'uuid':item.uuid, 'dev':disk.dev});
        }
        var remove_btn = genActBtn(false, 'Remove Disk', 'Remove', 'del_device', host, {'uuid':item.uuid, 'dev':disk.dev});
        tbl += host ? `<td>${remove_btn}${addon_btn}</td></tr>` : `</tr>`;
      });
    } else if (key === 'nets') {
      const nets = JSON.parse(item[key]);
      nets.forEach(net => {
        tbl += `<tr><th class="truncate">${net.type}</th><td colspan="${colspan}" class="truncate" title="${net.mac}">${net.mac}</td>`;
        var remove_btn = genActBtn(false, 'Remove netcard', 'Remove', 'del_device', host, {'uuid':item.uuid, 'dev':net.mac});
        if (item['state'] === 'RUN') {
            remove_btn += genActBtn(false, 'Net Stats', 'NetStats', 'netstats', host, {'uuid':item.uuid, 'dev':net.mac});
        }
        tbl += host ? `<td>${remove_btn}</td></tr>`: `</tr>`;
      });
    } else if (key === 'mdconfig') {
      const mdconfig = JSON.parse(item[key]);
      for(var mdkey in mdconfig) {
        tbl += `<tr><th class="truncate">${mdkey}</th><td colspan="3" class="truncate">${mdconfig[mdkey]}</td></tr>`;
      }
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
      if (item.uuid === curr_vm() && ['uuid'].includes(key)) style +=' current';
      tbl += `<tr><th class="${style}">${key}</th><td colspan="3" class="${style}">${item[key]}</td></tr>`;
    }
  }
  tbl += '</table>';
  return tbl;
}
function manage_vm(kvmhost, uuid) {
  set_curr(kvmhost, uuid);
  flush_sidebar(kvmhost);
  showView("manage_vm");
  getjson('GET', `/vm/list/${kvmhost}/${uuid}`, function(resp){
    const result = JSON.parse(resp);
    var btn = genActBtn(true, 'Show XML', 'fa-file-code-o', 'show_xml', kvmhost, {'uuid':result.guest.uuid});
    btn += genActBtn(true, 'Control Panel', 'fa-ambulance', 'show_vmui', kvmhost, {'uuid':result.guest.uuid});
    if(result.guest.state === 'RUN') {
      btn += genActBtn(true, 'Console', 'fa-terminal', 'ttyconsole', kvmhost, {'uuid':result.guest.uuid});
      btn += genActBtn(true, 'Display View', 'fa-desktop', 'display', kvmhost, {'uuid':result.guest.uuid});
      btn += genActBtn(true, 'Reset VM', 'fa-repeat', 'reset', kvmhost, {'uuid':result.guest.uuid});
      btn += genActBtn(true, 'Stop VM', 'fa-power-off', 'stop', kvmhost, {'uuid':result.guest.uuid});
      btn += genActBtn(true, 'ForceStop VM', 'fa-plug', 'force_stop', kvmhost, {'uuid':result.guest.uuid});
    } else {
      btn += genActBtn(true, 'Start VM', 'fa-play', 'start', kvmhost, {'uuid':result.guest.uuid});
      btn += genActBtn(true, 'Undefine', 'fa-trash', 'undefine', kvmhost, {'uuid':result.guest.uuid});
    }
    btn += genActBtn(true, 'Add CDROM', 'fa-floppy-o', 'add_cdrom', kvmhost, {'uuid':result.guest.uuid});
    btn += genActBtn(true, 'Add NET', 'fa-wifi', 'add_net', kvmhost, {'uuid':result.guest.uuid});
    btn += genActBtn(true, 'Add DISK', 'fa-database', 'add_disk', kvmhost, {'uuid':result.guest.uuid});
    btn += genActBtn(true, 'Refresh VM', 'fa-refresh fa-spin', 'manage_vm', kvmhost, {'uuid':result.guest.uuid});
    btn += `<button title="Close" class="close" onclick="vmlist('${kvmhost}');"><h2>&times;</h2></button>`;
    const table = genVmsTBL(result.guest, kvmhost);
    const title = result.guest.state == "RUN" ? `<h2 class="highlight">GUEST</h2>` : `<h2>GUEST</h2>`;
    const tbl = genWrapper("vms-wrapper", title, btn, table);
    document.getElementById("vm_info").innerHTML = tbl;
  });
}
function show_vms(kvmhost, vms) {
  var tbl = '';
  vms.forEach(item => {
    const table = genVmsTBL(item);
    var btn = genActBtn(true, 'Show XML', 'fa-file-code-o', 'show_xml', kvmhost, {'uuid':item.uuid});
    btn += genActBtn(true, 'Control Panel', 'fa-ambulance', 'show_vmui', kvmhost, {'uuid':item.uuid, 'backlist':'1'});
    if (item.state === "RUN") {
      btn += genActBtn(true, 'VM IPAddress', 'fa-gg', 'get_vmip', kvmhost, {'uuid':item.uuid});
    } else {
      btn += genActBtn(true, 'Start VM', 'fa-play', 'start', kvmhost, {'uuid':item.uuid, 'backlist':'1'});
      btn += genActBtn(true, 'Undefine', 'fa-trash', 'undefine', kvmhost, {'uuid':item.uuid});
    }
    btn += genActBtn(true, 'Manage VM', 'fa-cog fa-spin fa-lg', 'manage_vm', kvmhost, {'uuid':item.uuid});
    const title = item.state == "RUN" ? '<h2 class="highlight">GUEST</h2>' : '<h2>GUEST</h2>';
    tbl += genWrapper("vms-wrapper", title, btn, table);
  });
  return tbl;
}
function show_host(kvmhost, more_info) {
  var host = getHost(kvmhost);
  delete host.vars;
  var btn = genActBtn(true, 'Refresh VM List', 'fa-refresh fa-spin', 'vmlist', host.name);
  btn += genActBtn(true, 'Create VM', 'fa-tasks', 'create_vm', host.name);
  const table = genVmsTBL(Object.assign({}, host, more_info));
  return genWrapper('host-wrapper', `<h2 class="highlight">${host.name.toUpperCase()}</h2>`, btn, table);
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
    const btn = `<button title="Close" class="close" onclick="this.closest('dialog').close();"><h2>&times;</h2></button>`;
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
    link.classList.remove('current');
    if(link.querySelector('[name="host"]').innerHTML === kvmhost) {
      link.classList.add('current');
      if(count) link.querySelector(`[name="count"]`).innerHTML = count;
    }
  });
}
function vmlist(kvmhost) {
  document.getElementById("vms").innerHTML = '';
  document.getElementById("host").innerHTML = '';
  var url = '/vm/list/';
  if(kvmhost !== 'ALL VMS') {
    url += kvmhost;
    set_curr(kvmhost);
  }
  getjson('GET', url, function(resp) {
    const result = JSON.parse(resp);
    if(result.result !== 'OK') { Alert('error', 'vmlist', 'Get VM List'); return; };
    const guest = result.guest;
    flush_sidebar(kvmhost, kvmhost == 'ALL VMS' ? `(${guest.length})` : `(${result.host.active}/${result.host.totalvm})`);
    if(kvmhost === 'ALL VMS') {
      var tbl = '';
      guest.forEach(item => {
        const btn = `<button title='GOTO Manager' onclick='manage_vm("${item.kvmhost}", "${item.uuid}")'><i class="fa fa-cog fa-spin fa-lg"></i></button>`;
        const table = genVmsTBL(item);
        tbl += genWrapper("vms-wrapper", "<h2>GUEST</h2>", btn, table);
      });
      document.getElementById("vms").innerHTML = tbl;
      const newArray = guest.map(item => {
        const { kvmhost, arch } = item;
        return { kvmhost, arch };
      });
      tbl = '<table>';
      processJsonArray(newArray).forEach(item => {
        tbl += `<tr><th title='host arch'>${item.arch}</th><td title='total vms'>${item.vms}</td><td><a href='#' title='GOTO Manager' onclick='vmlist("${item.kvmhost}")'>${item.kvmhost}</a></td></tr>`;
      });
      tbl += '</table>';
      document.getElementById("host").innerHTML = genWrapper('host-wrapper', `<h2 class="highlight">Summary</h2>`, '', tbl);
    } else {
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
  getjson('GET', `/vm/xml/${host}/${uuid}`, function(resp) {
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
  getjson('GET', `/vm/ui/${curr_host()}/${curr_vm()}?epoch=${epoch}`, function(resp) {
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
function show_vmui(host, uuid, backlist = null) {
  set_curr(host, uuid);
  const btn = document.getElementById('vmui').querySelector('.close');
  const btn_mail = document.getElementById('vmuimail').querySelector('.close');
  if (backlist) {
    btn.onclick = function(){showView("hostlist");};
  } else {
    btn.onclick = function(){showView("manage_vm");};
  }
  btn_mail.onclick = btn.onclick;
  showView('vmui');
}
function start(host, uuid, backlist = null) {
  set_curr(host, uuid);
  if (confirm(`Start ${uuid}?`)) {
    getjson('GET', `/vm/start/${host}/${uuid}`, function(resp) {
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
    getjson('GET', `/vm/reset/${host}/${uuid}`, getjson_result);
  }
}
function stop(host, uuid, force=false) {
  set_curr(host, uuid);
  if (confirm(`${force ? 'Force ' : ''}Stop ${uuid}?`)) {
    getjson('GET', `/vm/stop/${host}/${uuid}${force ? '?force=true' : ''}`, function(resp) {
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
    getjson('GET', `/vm/delete/${host}/${uuid}`, function(resp){ getjson_result(resp); vmlist(host); });
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
function get_vmip(host, uuid) {
  set_curr(host, uuid);
  getjson('GET', `/vm/ipaddr/${host}/${uuid}`, getjson_result);
}
function del_device(host, uuid, dev) {
  set_curr(host, uuid, dev);
  if (confirm(`delete device /${host}/${uuid}/${dev} ?`)) {
    getjson('POST', `/vm/detach_device/${host}/${uuid}?dev=${dev}`, function(resp) {
      getjson_result(resp);
      manage_vm(curr_host(), curr_vm());
    });
  }
}
function on_changeiso(form) {
  getjson('POST', `/vm/cdrom/${curr_host()}/${curr_vm()}?dev=${curr_dev()}`,function(resp) {
      getjson_result(resp);
      manage_vm(curr_host(), curr_vm());
    }, getFormJSON(form));
  return false;
}
function disk_size(host, uuid, dev) {
  set_curr(host, uuid, dev);
  getjson('GET', `/vm/blksize/${curr_host()}/${curr_vm()}?dev=${dev}`, getjson_result);
}
function change_iso(host, uuid, dev) {
  set_curr(host, uuid, dev);
  showView('changecdrom');
  document.getElementById('isoname_list').innerHTML = genOption(get_iso());
}
function on_createvm(form) {
  getjson('POST', `/vm/create/${curr_host()}`, function(resp){
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
  getjson('GET', `/vm/freeip/`, function(resp) {
    const ips = JSON.parse(resp);
    document.getElementById('vm_ip').value = ips.cidr;
    document.getElementById('vm_gw').value = ips.gateway;
  });
}
function on_add(form) {
  function getLastLine(str) {
    const lines = str.split('\n');
    return lines[lines.length - 1];
  }
  var res = getFormJSON(form);
  const device = res.device;
  delete res.device;
  getjson('POST', `/vm/attach_device/${curr_host()}/${curr_vm()}?dev=${device}`, function(resp) {
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
  set_help(form, cpWithoutKeys(disks[0]['vars'], objs));
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
  set_help(form, cpWithoutKeys(nets[0]['vars'], objs));
  document.getElementById('net_list').innerHTML = genOption(nets);
}
function add_cdrom(host, uuid) {
  set_curr(host, uuid);
  showView('addcdrom');
  const form = document.getElementById("addcdrom_form");
  form.querySelector(`table[name="meta_data"]`).innerHTML = '';
  const cdroms = filterByKey(getDevice(host), 'devtype', 'iso');
  const objs = Object.keys(getFormJSON(form, false));
  set_help(form, cpWithoutKeys(cdroms[0]['vars'], objs));
  document.getElementById('cdrom_list').innerHTML = genOption(cdroms);
}
function on_modifydesc(form) {
  const res = getFormJSON(form);
  getjson('GET', `/vm/desc/${curr_host()}/${curr_vm()}?vm_desc=${res.vm_desc}`, function(resp) {
    getjson_result(resp);
    manage_vm(curr_host(), curr_vm());
  });
  return false;
}
function modify_desc(host, uuid) {
  set_curr(host, uuid);
  showView('modifydesc');
}
function on_modifymemory(form) {
  const res = getFormJSON(form);
  getjson('GET', `/vm/setmem/${curr_host()}/${curr_vm()}?vm_ram_mb=${res.vm_ram_mb}`,function(resp) {
    getjson_result(resp);
    manage_vm(curr_host(), curr_vm());
  });
  return false;
}
function modify_memory(host, uuid) {
  set_curr(host, uuid);
  showView('modifymemory');
}
function on_modifyvcpus(form) {
  const res = getFormJSON(form);
  getjson('GET', `/vm/setcpu/${curr_host()}/${curr_vm()}?vm_vcpus=${res.vm_vcpus}`,function(resp) {
    getjson_result(resp);
    manage_vm(curr_host(), curr_vm());
  });
  return false;
}
function modify_vcpus(host, uuid) {
  set_curr(host, uuid);
  showView('modifyvcpus');
}
function netstats(host, uuid, dev) {
  set_curr(host, uuid, dev);
  getjson('GET', `/vm/netstat/${curr_host()}/${curr_vm()}?dev=${dev}`, getjson_result);
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
/* ------------------------- */
window.addEventListener('load', function() {
  includeHTML();
  getjson('GET', '/tpl/host/', function (resp) {
    const result = JSON.parse(resp);
    if(result.result !== 'OK') { Alert('error', 'init', 'Get Host List'); return; }
    config.g_host = result.host;
    var mainMenu = `<a href='#' onclick='vmlist("ALL VMS")'><i class='fa fa-list-ol'></i><span name='host'>ALL VMS</span><span style='float:right;' name='count'></span></a>`;
    config.g_host.forEach(host => {
      mainMenu += `<a href='#' title="${host.arch}" onclick='vmlist("${host.name}")'><i class="fa fa-desktop"></i><span name='host'>${host.name}</span><span style='float:right;' name='count'></span></a>`;
    });
    document.getElementById("sidebar").innerHTML = mainMenu;
  });
  getjson('GET', `/tpl/iso/`, function(resp) { const result = JSON.parse(resp);if(result.result !== 'OK') { Alert('error', 'init', 'Get ISO List'); return; }; config.g_iso = result.iso; });
  getjson('GET', `/tpl/gold/`, function(resp) { const result = JSON.parse(resp);if(result.result !== 'OK') { Alert('error', 'init', 'Get Gold List'); return; }; config.g_gold = result.gold; });
  getjson('GET', `/tpl/device/`, function(resp) { const result = JSON.parse(resp);if(result.result !== 'OK') { Alert('error', 'init', 'Get Device List'); return; }; config.g_device = result.device; });
})
