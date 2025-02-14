var config = { g_hosts: {}, g_menu : [ { "name" : "About", "url" : "#", "submenu" : [ { "name" : "about", "url" : "javascript:about()" } ] } ] };
dialog = new Dialog();
function about() { alert("vmmagr"); }
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
    //<select name="devtype"><option value="disk">disk</option><option value="net">net</option><option value="iso">iso</option></select>
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
function getjson(method, url, callback, data) {
  var sendObject = null;
  if(null !== data && typeof data !== 'undefined') {
    sendObject = JSON.stringify(data);
    sendObject['epoch']=~~(Date.now()/1000);
  }
  xhr=new XMLHttpRequest();
  //xhr.addEventListener("load", transferComplete);
  //xhr.addEventListener("error", transferFailed);
  //xhr.addEventListener("abort", transferCanceled);
  xhr.onerror = function () { console.error(`${url} ${method} net error`); };
  xhr.ontimeout = function () { console.error(`${url} ${method} timeout`); };
  xhr.open(method, url, true);
  //xhr.setRequestHeader('Pragma', 'no-cache');
  xhr.setRequestHeader('Content-Type', 'application/json')
  xhr.timeout = 30000; // Set a timeout 30 seconds
  xhr.onreadystatechange = function() {
    if(this.readyState === 4 && this.status === 200) {
      console.log(`${method} ${url} ${xhr.response}`);
      callback(xhr.response);
      return;
    }
    if(xhr.readyState === 4 && xhr.status !== 0) {
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
}
function vmlist(host) {
  document.getElementById("vms").innerHTML = ''
  getjson('GET', `/vm/list/${host}`, function(res) {
    vms = JSON.parse(res);
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
    result = JSON.parse(res);
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
    result = JSON.parse(res);
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
    result = JSON.parse(res);
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
    result = JSON.parse(res);
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
    result = JSON.parse(res);
    if(result.result === 'OK') {
      dialog.open({
        dialogClass: 'custom',
        message: 'Console',
        template: `<embed width="640" height="480" src=${result.display} type="text/html"/>`
      })
      dialog.waitForUser().then((res) => { })
      //document.getElementById("display").src = result.display;
      //window.open(result.display, "_blank");
    } else {
      disperr(result.code, result.name, result.desc)
    }
  }, null);
}
function do_create(host, res) {
  if (res == false){ return; }
  getjson('POST', `/vm/create/${host}`, function(res) {
    result = JSON.parse(res);
    if(result.result === 'OK') {
      dispok('create vm OK');
      vmlist(host);
    } else {
      disperr(result.code, result.name, result.desc)
    }
  }, res);
}
function create_vm(host, arch) {
  dialog.open({
    dialogClass: 'custom',
    message: 'CreateVM',
    accept: 'Create',
    template: `<input type="hidden" name="vm_arch" value="${arch}">` +
      '<label>CPU:<input type="number" name="vm_vcpus" value="2" min="1" max="8"/></label>' +
      '<label>MEM(MB):<input type="number" name="vm_ram_mb" value="2048" min="1024" max="8192" step="1024"/></label>' +
      '<label>IPADDR:<input type="text" name="vm_ip" value="192.168.168.2/24"/></label>' +
      '<label>GATEWAY:<input type="text" name="vm_gw" value="192.168.168.1"/></label>' +
      '<label>DESC:<input type="text" name="vm_desc" value=""/></label>'
  })
  dialog.waitForUser().then((res) => { do_create(host, res); })
}
function gen_gold_list(jsonobj, id) {
  var lst = `<label>${id}<select name="${id}">`;
  // add empty value for data disk
  lst += `<option value="" selected>数据盘</option>`;
  jsonobj.forEach(item => {
    lst += `<option value="${item['name']}">${item['desc']}</option>`;
  });
  lst += '</select></label>';
  return lst;
}
function gen_dev_list(jsonobj, id, devtype) {
  var lst = `<label>${id}<select name="${id}">`;
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
    result = JSON.parse(res);
    if(result.result === 'OK') {
      dispok(`add OK ${res}`);
      vmlist(host);
    } else {
      disperr(result.code, result.name, result.desc)
    }
  }, res);
}
function add_disk(host, uuid) {
  getjson('GET', `/tpl/gold/${host}`, function(res) {
    var gold = JSON.parse(res);
    gold_lst = gen_gold_list(gold, 'Gold:');
    getjson('GET', `/tpl/device/${host}`, function(res) {
      var devs = JSON.parse(res);
      dev_lst = gen_dev_list(devs, 'Device:', 'disk');
      dialog.open({
        dialogClass: 'custom',
        message: 'Add Disk',
        accept: 'Add',
        template: `${dev_lst}${gold_lst}<label>Size(GB):<input type="number" name="size" value="10" min="1" max="1024"/></label>`
      })
      dialog.waitForUser().then((res) => { do_add(host, uuid, res); })
    }, null);
  }, null);
}
function add_net(host, uuid) {
  getjson('GET', `/tpl/device/${host}`, function(res) {
    var devs = JSON.parse(res);
    dev_lst = gen_dev_list(devs, 'Device:', 'net');
    dialog.open({
      dialogClass: 'custom',
      message: 'Add Network',
      accept: 'Add',
      template: `${dev_lst}`
    })
    dialog.waitForUser().then((res) => { do_add(host, uuid, res); })
  }, null);
}
function add_iso(host, uuid) {
  getjson('GET', `/tpl/device/${host}`, function(res) {
    var devs = JSON.parse(res);
    dev_lst = gen_dev_list(devs, 'Device:', 'iso');
    dialog.open({
      dialogClass: 'custom',
      message: 'Add ISO',
      accept: 'Add',
      template: `${dev_lst}`
    })
    dialog.waitForUser().then((res) => { do_add(host, uuid, res); })
  }, null);
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
  document.getElementById("sidebar").innerHTML = mainMenu;
}, null);
///////////////////////////////////////////////////////////
// <form id="myform"></form>
// const form = document.getElementById('myform');
// form.addEventListener('submit', function(event) {
//   event.preventDefault(); // Prevents the default form submission
//   const res = getFormJSON(form);
//   console.log(res)
// }
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
