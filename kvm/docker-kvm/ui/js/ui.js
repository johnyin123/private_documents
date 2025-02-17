var config = { g_hosts: {}, g_menu : [ { "name" : "About", "url" : "#", "submenu" : [ { "name" : "about", "url" : "javascript:about()" } ] } ] };
function about() { showView('about'); }
function gen_act(smsg, action, host, parm2, icon) {
  return `<button class='hovertext' data-hover='${smsg}' onclick='${action}("${host}", "${parm2}")'><i class="fa ${icon}"></i></button>`;
}
function show_vms(host, vms) {
  delete vms[0].gateway;
  delete vms[0].vcpus;
  delete vms[0].maxmem;
  var table = "<table><tr>";
  for(var key in vms[0]) {
    table += `<th>${key}</th>`;
  }
  if(vms.length > 0) {
    table += "<th>Actions</th></tr>";
  }
  vms.forEach(item => {
    table += "<tr>";
    delete item.gateway;
    delete item.vcpus;
    delete item.maxmem;
    for(var key in item) {
      table += `<td>${item[key]}</td>`;
    }
    table += "<td>"
    table += gen_act('VNC', 'display', host, item.uuid, 'fa-television')
    table += gen_act('Start', 'start', host, item.uuid, 'fa-play')
    table += gen_act('Stop', 'stop', host, item.uuid, 'fa-power-off')
    table += gen_act('ForceStop', 'force_stop', host, item.uuid, 'fa-plug')
    table += gen_act('Undefine', 'undefine', host, item.uuid, 'fa-times')
    table += gen_act('Add ISO', 'add_iso', host, item.uuid, 'fa-plus')
    table += gen_act('Add NET', 'add_net', host, item.uuid, 'fa-plus')
    table += gen_act('Add DISK', 'add_disk', host, item.uuid, 'fa-plus')
    table += "</td></tr>";
  });
  table += "</table>";
  return table;
}
function show_host(host) {
  // no show last_modified
  delete host.last_modified;
  var table = "<table><tr>";
  for(var key in host) {
    table += `<th>${key}</th>`;
  }
  table += "<th>Actions</th></tr><tr>";
  for(var key in host) {
    table += `<td>${host[key]}</td>`;
  }
  table += `<td>${gen_act('Create VM', 'create_vm', host.name, host.arch, 'fa-plus')}</td></tr></table>`;
  return table;
}
function dispok(msg) {
  alert(msg);
}
function disperr(code, name, desc) {
  alert(`${code} ${name} ${desc}`);
}
function overlayon() {
  document.getElementById("overlay").style.display = "block";
}
function overlayoff() {
  document.getElementById("overlay").style.display = "none";
}
function getjson(method, url, callback, data) {
  var sendObject = null;
  if(null !== data && typeof data !== 'undefined') {
    sendObject = JSON.stringify(data);
    sendObject['epoch']=~~(Date.now()/1000);
  }
  var xhr = new XMLHttpRequest();
  //xhr.addEventListener("load", transferComplete);
  //xhr.addEventListener("error", transferFailed);
  //xhr.addEventListener("abort", transferCanceled);
  xhr.onerror = function () { overlayoff(); console.error(`${url} ${method} net error`); };
  xhr.ontimeout = function () { overlayoff(); console.error(`${url} ${method} timeout`); };
  xhr.open(method, url, true);
  //xhr.setRequestHeader('Pragma', 'no-cache');
  xhr.setRequestHeader('Content-Type', 'application/json')
  xhr.timeout = 30000; // Set a timeout 30 seconds
  xhr.onreadystatechange = function() {
    if(this.readyState === 4 && this.status === 200) {
      overlayoff();
      console.log(`${method} ${url} ${xhr.response}`);
      callback(xhr.response);
      return;
    }
    if(xhr.readyState === 4 && xhr.status !== 0) {
      overlayoff();
      console.error(`${url} ${method} ${xhr.status} ${xhr.statusText}`);
      disperr(xhr.status, method, `${url} ${xhr.statusText}`);
    }
    return;
  }
  if(null !== sendObject) {
    xhr.send(sendObject);
  } else {
    xhr.send();
  }
  overlayon();
}
function vmlist(host) {
  document.getElementById("vms").innerHTML = ''
  getjson('GET', `/vm/list/${host}`, function(res) {
    var vms = JSON.parse(res);
    document.getElementById("vms").innerHTML = show_vms(host, vms);
  }, null);
}
function on_menu_host(host, n) {
  document.getElementById("host").innerHTML = '';
  document.getElementById("host").innerHTML = show_host(host[n]);
  vmlist(host[n].name);
  showView("hostlist");
}
function start(host, uuid) {
  getjson('GET', `/vm/start/${host}/${uuid}`, function(res) {
    var result = JSON.parse(res);
    if(result.result === 'OK') {
      dispok('start vm OK');
      vmlist(host);
    } else {
      disperr(result.code, result.name, result.desc)
    }
  }, null);
}
function stop(host, uuid) {
  getjson('GET', `/vm/stop/${host}/${uuid}`, function(res) {
    var result = JSON.parse(res);
    if(result.result === 'OK') {
      dispok('stop vm OK');
      vmlist(host);
    } else {
      disperr(result.code, result.name, result.desc)
    }
  }, null);
}
function force_stop(host, uuid) {
  getjson('DELETE', `/vm/stop/${host}/${uuid}`, function(res) {
    var result = JSON.parse(res);
    if(result.result === 'OK') {
      dispok('force stop vm OK');
      vmlist(host);
    } else {
      disperr(result.code, result.name, result.desc)
    }
  }, null);
}
function undefine(host, uuid) {
  getjson('GET', `/vm/delete/${host}/${uuid}`, function(res) {
    var result = JSON.parse(res);
    if(result.result === 'OK') {
      dispok('undefine vm OK');
      vmlist(host);
    } else {
      disperr(result.code, result.name, result.desc)
    }
  }, null);
}
function display(host, uuid) {
  getjson('GET', `/vm/display/${host}/${uuid}`, function(res) {
    var result = JSON.parse(res);
    if(result.result === 'OK') {
      //document.getElementById("display").src = result.display;
      window.open(result.display, "_blank");
    } else {
      disperr(result.code, result.name, result.desc)
    }
  }, null);
}
function do_create(host, res) {
  if (res == false){ return; }
  getjson('POST', `/vm/create/${host}`, function(res) {
    var result = JSON.parse(res);
    if(result.result === 'OK') {
      dispok('create vm OK');
      vmlist(host);
    } else {
      disperr(result.code, result.name, result.desc)
    }
  }, res);
}
function create_vm(host, arch) {
  const form = document.getElementById('createvm_form');
  form.addEventListener('submit', function(event) {
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    console.log(`createvm : ${res}`);
    do_create(host, res);
    showView('hostlist');
  });
  showView('createvm');
}
function gen_gold_list(jsonobj, id, text) {
  var lst = `<label>${text}<select name="${id}">`;
  // add empty value for data disk
  lst += `<option value="" selected>数据盘</option>`;
  jsonobj.forEach(item => {
    lst += `<option value="${item['name']}">${item['desc']}</option>`;
  });
  lst += '</select></label>';
  return lst;
}
function gen_dev_list(jsonobj, id, devtype, text) {
  var lst = `<label>${text}<select name="${id}">`;
  jsonobj.forEach(item => {
    if(devtype === item['devtype']) {
      lst += `<option value="${item['name']}">${item['desc']}</option>`;
    }
  });
  lst += '</select></label>';
  return lst;
}
function do_add(host, uuid, res) {
  if (res == false){ return; }
  console.log(JSON.stringify(res));
  getjson('POST', `/vm/attach_device/${host}/${uuid}/${res.device}`, function(res) {
    var result = JSON.parse(res);
    if(result.result === 'OK') {
      dispok(`add OK ${res}`);
      vmlist(host);
    } else {
      disperr(result.code, result.name, result.desc)
    }
  }, res);
}
function add_disk(host, uuid) {
  const form = document.getElementById('adddisk_form');
  const goldlst = document.getElementById('gold_list');
  const devlst = document.getElementById('dev_list');
  getjson('GET', `/tpl/device/${host}`, function(res) {
    var devs = JSON.parse(res);
    devlst.innerHTML = gen_dev_list(devs, 'device', 'disk', 'Disk:');
  }, null);
  getjson('GET', `/tpl/gold/${host}`, function(res) {
    var gold = JSON.parse(res);
    goldlst.innerHTML = gen_gold_list(gold, 'gold', 'Gold:');
  }, null);
  form.addEventListener('submit', function(event) {
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    console.log(`add disk : ${res}`);
    do_add(host, uuid, res);
    showView('hostlist');
  });
  showView('adddisk');
}
function add_net(host, uuid) {
  const form = document.getElementById('addnet_form');
  const netlst = document.getElementById('net_list');
  getjson('GET', `/tpl/device/${host}`, function(res) {
    var devs = JSON.parse(res);
    netlst.innerHTML = gen_dev_list(devs, 'device', 'net', 'Network:');
  }, null);
  form.addEventListener('submit', function(event) {
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    console.log(`add net : ${res}`);
    do_add(host, uuid, res);
    showView('hostlist');
  });
  showView('addnet');
}
function add_iso(host, uuid) {
  const form = document.getElementById('addiso_form');
  const isolst = document.getElementById('iso_list');
  getjson('GET', `/tpl/device/${host}`, function(res) {
    var devs = JSON.parse(res);
    isolst.innerHTML = gen_dev_list(devs, 'device', 'iso', 'ISO:');
  }, null);
  form.addEventListener('submit', function(event) {
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    console.log(`add iso : ${res}`);
    do_add(host, uuid, res);
    showView('hostlist');
  });
  showView('addiso');
}
getjson('GET', '/tpl/host', function (res) {
  config.g_hosts = JSON.parse(res);
  var mainMenu = "<ul>";
  mainMenu += "<li>";
  mainMenu += "<a href='#'>KVMHosts</a><ul>"
  for(var n = 0; n < config.g_hosts.length; n++) {
    mainMenu += "<li>";
    mainMenu += `<a href='#' onclick='on_menu_host(config.g_hosts, ${n})'>${config.g_hosts[n].name}</a>`;
    mainMenu += "</li>";
  }
  mainMenu += "</ul>";
  /////////////////////////
  mainMenu += "</li>";
  for(var m = 0; m < config.g_menu.length; m++) {
    mainMenu += "<li>";
    mainMenu += `<a href='${config.g_menu[m].url}'>${config.g_menu[m].name}</a>`;
    if(config.g_menu[m].submenu.length > 0) {
      mainMenu += "<ul>";
      for(var n = 0; n < config.g_menu[m].submenu.length; n++) {
        mainMenu += "<li>";
        mainMenu += `<a href='${config.g_menu[m].submenu[n].url}'>${config.g_menu[m].submenu[n].name}</a>`;
        mainMenu += "</li>";
      }
      mainMenu += "</ul>";
    }
    mainMenu += "</li>";
  }
  mainMenu += "</ul>";
  document.getElementById("sidebar").innerHTML = mainMenu;
}, null);
///////////////////////////////////////////////////////////
// <form id="myform"></form>
// const form = document.getElementById('myform');
// form.addEventListener('submit', function(event) {
//   event.preventDefault(); // Prevents the default form submission
//   const res = getFormJSON(form);
//   console.log(res)
// });
function getFormJSON(form) {
  const data = new FormData(form);
  return Array.from(data.keys()).reduce((result, key) => {
    result[key] = data.get(key);
    return result;
  }, {});
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
