var g_menu = [ { "name" : "About", "url" : "#", "submenu" : [ { "name" : "about", "url" : "about.html" } ] } ]
var g_hosts='';
dialog = new Dialog();
function gen_act(smsg, action, host, parm2, icon) {
  return `<button class='hovertext' data-hover='${smsg}' onclick='${action}("${host}", "${parm2}")'><i class="fa ${icon}"></i></button>`;
    }
function show_vms(host, vms) {
  var table = "<table><tr>";
  for(var key in vms[0]) {
    table += `<th>${key}</th>`;
  }
  if(vms.length > 0) {
    table += "<th>Actions</th></tr>";
  }
  vms.forEach(item => {
    table += "<tr>";
    for(var key in item) {
      table += `<td>${item[key]}</td>`;
    }
    table += "<td>"
    table += gen_act('VNC', 'display', host, item.uuid, 'fa-television')
    table += '&nbsp;'
    table += gen_act('Start', 'start', host, item.uuid, 'fa-play')
    table += '&nbsp;'
    table += gen_act('Stop', 'stop', host, item.uuid, 'fa-power-off')
    table += '&nbsp;'
    table += gen_act('Undefine', 'undefine', host, item.uuid, 'fa-times')
    table += '&nbsp;'
    table += gen_act('Add ISO', 'add_iso', host, item.uuid, 'fa-plus')
    table += '&nbsp;'
    table += gen_act('Add NET', 'add_net', host, item.uuid, 'fa-plus')
    table += '&nbsp;'
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
function gethost(res) {
  g_hosts = JSON.parse(res);
  var mainMenu = "<ul>";
  mainMenu += "<li>";
  mainMenu += "<a href='#'>KVMHosts</a><ul>"
  for(var n = 0; n < g_hosts.length; n++) {
    mainMenu += "<li>";
    mainMenu += `<a href='#' onclick='on_menu_host(g_hosts, ${n})'>${g_hosts[n].name}</a>`;
    mainMenu += "</li>";
  }
  mainMenu += "</ul>";
  /////////////////////////
  mainMenu += "</li>";
  for(var m = 0; m < g_menu.length; m++) {
    mainMenu += "<li>";
    mainMenu += `<a href='${g_menu[m].url}'>${g_menu[m].name}</a>`;
    if(g_menu[m].submenu.length > 0) {
      mainMenu += "<ul>";
      for(var n = 0; n < g_menu[m].submenu.length; n++) {
        mainMenu += "<li>";
        mainMenu += `<a href='${g_menu[m].submenu[n].url}'>${g_menu[m].submenu[n].name}</a>`;
        mainMenu += "</li>";
      }
      mainMenu += "</ul>";
    }
    mainMenu += "</li>";
  }
  document.getElementById("mainMenu").innerHTML = mainMenu;
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
  document.getElementById("host").innerHTML = ''
  document.getElementById("host").innerHTML = show_host(host[n]);
  vmlist(host[n].name)
}
function start(host, uuid) {
  getjson('GET', `/vm/start/${host}/${uuid}`, function(res) {
    result = JSON.parse(res);
    if(result.result === 'OK') {
      dispok('start vm OK');
    } else {
      disperr(result.code, result.name, result.desc)
    }
  }, null);
}
function stop(host, uuid) {
  getjson('GET', `/vm/stop/${host}/${uuid}`, function(res) {
    result = JSON.parse(res);
    if(result.result === 'OK') {
      dispok(' stop vm OK');
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
      dispok('display OK');
      window.open(result.display, "_blank");
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
      '<input type="text" name="vm_vcpus" value="2">' +
      '<input type="text" name="vm_ram_mb" value="2048">' +
      '<input type="text" name="vm_ip" value="192.168.168.2/32">' +
      '<input type="text" name="vm_gw" value="192.168.168.1">' +
      '<input type="text" name="vm_desc" value="">'
  })
  dialog.waitForUser().then((res) => { do_create(host, res); })
}
function gen_gold_list(jsonobj, id) {
  var lst = `<label>${id}</label><select name="${id}">`;
  lst += `<option value="" selected>数据盘</option>`;
  jsonobj.forEach(item => {
    lst += `<option value="${item['name']}">${item['desc']}</option>`;
  });
  lst += '</select>';
  return lst;
}
function gen_dev_list(jsonobj, id, devtype) {
  var lst = `<label>${id}</label><select name="${id}">`;
  jsonobj.forEach(item => {
    if(devtype === item['devtype']) {
      lst += `<option value="${item['name']}">${item['desc']}</option>`;
    }
  });
  lst += '</select>';
  return lst;
}
function do_add(host, res) {
  if (res == false){ return; }
  console.log(JSON.stringify(res));
}
function add_disk(host, uuid) {
  getjson('GET', `/tpl/gold/${host}`, function(res) {
     var gold = JSON.parse(res);
     gold_lst = gen_gold_list(gold, 'gold');
     getjson('GET', `/tpl/device/${host}`, function(res) {
        var devs = JSON.parse(res);
        dev_lst = gen_dev_list(devs, 'device', 'disk');
        dialog.open({
          dialogClass: 'custom',
          message: 'Add Disk',
          accept: 'Add',
          template: `${dev_lst}${gold_lst}<input type="text" name="size" value="5G">`
        })
        dialog.waitForUser().then((res) => { do_add(host, res); })
     }, null);
  }, null);
}
function add_net(host, uuid) {
  getjson('GET', `/tpl/device/${host}`, function(res) {
     var devs = JSON.parse(res);
     dev_lst = gen_dev_list(devs, 'device', 'net');
     dialog.open({
       dialogClass: 'custom',
       message: 'Add Network',
       accept: 'Add',
       template: `${dev_lst}`
     })
     dialog.waitForUser().then((res) => { do_add(host, res); })
  }, null);
}
function add_iso(host, uuid) {
  getjson('GET', `/tpl/device/${host}`, function(res) {
     var devs = JSON.parse(res);
     dev_lst = gen_dev_list(devs, 'device', 'iso');
     dialog.open({
       dialogClass: 'custom',
       message: 'Add ISO',
       accept: 'Add',
       template: `${dev_lst}`
     })
     dialog.waitForUser().then((res) => { do_add(host, res); })
  }, null);
}
getjson('GET', '/tpl/host', gethost, null);
// <select>
//   <optgroup label="Fruits">
//     <option value="apple">Apple</option>
//     <option value="banana">Banana</option>
//     <option value="orange">Orange</option>
//   </optgroup>
//   <optgroup label="Vegetables">
//     <option value="carrot">Carrot</option>
//     <option value="celery">Celery</option>
//     <option value="spinach">Spinach</option>
//   </optgroup>
// </select>
