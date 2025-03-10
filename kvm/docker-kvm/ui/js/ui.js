var config = { g_hosts: {} };
function about() { showView('about'); }
function gen_gold_list(jsonobj) {
  var lst = '';
  // add empty value for data disk
  lst += `<option value="" selected>数据盘</option>`;
  jsonobj.forEach(item => {
    lst += `<option value="${item['name']}">${item['desc']}</option>`;
  });
  return lst;
}
function gen_dev_list(jsonobj, devtype) {
  var lst = '';
  jsonobj.forEach(item => {
    if(devtype === item['devtype']) {
      lst += `<option value="${item['name']}">${item['desc']}</option>`;
    }
  });
  return lst;
}
function gen_act(smsg, action, host, parm2, icon) {
  return `<button title='${smsg}' onclick='${action}("${host}", "${parm2}")'><i class="fa ${icon}"></i></button>`;
}
function show_all_db_vms(view) {
  dbvms = document.getElementById("dbvms");
  dbvms_total = document.getElementById("dbvms-total");
  getjson('GET', `/vm/list/`, function(res) {
    var vms = JSON.parse(res);
    dbvms_total.innerHTML = vms.length;
    var table = '';
    vms.forEach(item => {
      table += `<div class="vms-wrapper">`;
      table += `<div class="vms-wrapper-header"><h2>GUEST</h2></div>`;
      table += `<table>`;
      for(var key in item) {
        table += `<tr><th width="20%">${key}</th><td>${item[key]}</td></tr>`;
      }
      table += "</table>";
      table += "</div>";
    });
    dbvms.innerHTML = table;
  });
  showView(view);
}
function show_vms(host, vms) {
  var table = '';
  vms.forEach(item => {
    table += `<div class="vms-wrapper">`;
    table += `<div class="vms-wrapper-header vmstate${item.state}"><h2>GUEST</h2><div>`;
    if(item.state === 1) {
      table += gen_act('VNC', 'display', host, item.uuid, 'fa-desktop');
      table += gen_act('Stop', 'stop', host, item.uuid, 'fa-power-off');
      table += gen_act('ForceStop', 'force_stop', host, item.uuid, 'fa-plug');
    } else {
      table += gen_act('Start', 'start', host, item.uuid, 'fa-play');
      table += gen_act('Undefine', 'undefine', host, item.uuid, 'fa-trash');
    } 
    table += gen_act('Add ISO', 'add_iso', host, item.uuid, 'fa-floppy-o');
    table += gen_act('Add NET', 'add_net', host, item.uuid, 'fa-wifi');
    table += gen_act('Add DISK', 'add_disk', host, item.uuid, 'fa-folder-o');
    table += `</div></div>`;
    table += `<table>`;
    for(var key in item) {
      table += `<tr><th width="20%">${key}</th><td>${item[key]}</td></tr>`;
    }
    table += "</table>";
    table += "</div>";
  });
  return table;
}
function show_host(host) {
  // delete host.last_modified;
  var table = '';
  table += `<div class="host-wrapper">`;
  table += `<div class="host-wrapper-header"><h2>KVM HOST</h2><div>`;
  table += gen_act('Create VM', 'create_vm', host.name, host.arch, 'fa-tasks');
  table += `</div></div>`;
  table += `<table>`;
  for(var key in host) {
    table += `<tr><th width="20%">${key}</th><td>${host[key]}</td></tr>`;
  }
  table += '</table>';
  table += '</div>';
  return table;
}
///////////////////////////////////////////////////////////
// <form id="myform"></form>
// const form = document.getElementById('myform');
// form.addEventListener('submit', function(event) {
//   event.preventDefault(); // Prevents the default form submission
//   const res = getFormJSON(form);
//   console.log(res)
// }, { once: true });
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
function Alert(message) {
  const div_alert = document.getElementById("alert");
  if (div_alert !== null) {
    div_alert.innerHTML = message;
    showView('alert');
  } else {
    alert(message);
  }
}
function dispok(msg) {
  Alert(`
  <div class="form-wrapper">
    <div class="form-wrapper-header success"><h2>SUCCESS</h2><button title="Close" class="close" onclick="showView('hostlist')"><h2>&times;</h2></button></div>
    <form><pre style="white-space: pre-wrap;">${msg}</pre></form>
  </div>`);
}
function disperr(code, name, desc) {
  Alert(`
  <div class="form-wrapper">
    <div class="form-wrapper-header error"><h2>${name}: ${code}</h2><button title="Close" class="close" onclick="showView('hostlist')"><h2>&times;</h2></button></div>
    <form><pre style="white-space: pre-wrap;">${desc}</pre></form>
  </div>`);
}
function overlayon() {
  const overlay = document.getElementById("overlay");
  if (overlay !== null) {
    overlay.style.display = "block";
  }
}
function overlayoff() {
  const overlay = document.getElementById("overlay");
  if (overlay !== null) {
    overlay.style.display = "none";
  }
}
function getjson(method, url, callback, data=null, stream=null, tmout=30000) {
  /* Set default timeout 30 seconds*/
  var sendObject = null;
  if(null !== data && typeof data !== 'undefined') {
    sendObject = JSON.stringify(data);
  }
  var xhr = new XMLHttpRequest();
  //xhr.addEventListener("load", transferComplete);
  //xhr.addEventListener("error", transferFailed);
  //xhr.addEventListener("abort", transferCanceled);
  xhr.onerror = function () { overlayoff(); console.error(`${url} ${method} net error`); };
  xhr.onabort = function() { overlayoff(); console.error(`${url} ${method} abort`); };
  xhr.ontimeout = function () { overlayoff(); console.error(`${url} ${method} timeout`); };
  xhr.onloadend = function() { console.error(`${url} ${method} xhr.onloadend, as finally`); };
  xhr.open(method, url, true);
  //xhr.setRequestHeader('Pragma', 'no-cache');
  xhr.setRequestHeader('Content-Type', 'application/json')
  xhr.timeout = tmout;
  xhr.onreadystatechange = function() {
    if(this.readyState === 3 && this.status === 200) {
      if (stream && typeof(stream) == "function") {
        stream(xhr.responseText);
      }
      return;
    }
    if(this.readyState === 4 && this.status === 200) {
      overlayoff();
      console.log(`${method} ${url} ${xhr.response}`);
      if (callback && typeof(callback) == "function") {
        callback(xhr.response);
      }
      return;
    }
    if(xhr.readyState === 4 && xhr.status !== 0) {
      overlayoff();
      console.error(`${method} ${url} ${xhr.status} ${xhr.response}`);
      try {
        result = JSON.parse(xhr.response);
        disperr(result.code, result.name, result.desc);
      } catch (e) {
        disperr(xhr.status, `${method} ${url}`, `${xhr.response}`);
      }
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
  });
}
function on_menu_host(host, n) {
  document.getElementById("host").innerHTML = '';
  document.getElementById("host").innerHTML = show_host(host[n]);
  vmlist(host[n].name);
  showView("hostlist");
}
function start(host, uuid) {
  getjson('GET', `/vm/start/${host}/${uuid}`, function(res) {
    dispok(`start vm ${res}`);
    vmlist(host);
  });
}
function stop(host, uuid) {
  getjson('GET', `/vm/stop/${host}/${uuid}`, function(res) {
    dispok(`stop vm ${res}`);
    vmlist(host);
  });
}
function force_stop(host, uuid) {
  getjson('DELETE', `/vm/stop/${host}/${uuid}`, function(res) {
    dispok(`force stop vm ${res}`);
    vmlist(host);
  });
}
function undefine(host, uuid) {
  getjson('GET', `/vm/delete/${host}/${uuid}`, function(res) {
    dispok(`undefine vm ${res}`);
    vmlist(host);
  });
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
  });
}
function do_create(host, res) {
  getjson('POST', `/vm/create/${host}`, function(res) {
    dispok(`create vm ${res}`);
    vmlist(host);
  }, res);
}
function create_vm(host, arch) {
  const form = document.getElementById('createvm_form');
  form.addEventListener('submit', function(event) {
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    do_create(host, res);
    showView('hostlist');
  }, { once: true });
  form.reset();
  showView('createvm');
}
function do_add(host, uuid, res) {
  console.log(JSON.stringify(res));
  const overlay_output = document.querySelector("#overlay_output");
  getjson('POST', `/vm/attach_device/${host}/${uuid}/${res.device}`, function(res) {
    dispok('Add Device OK');
    vmlist(host);
    overlay_output.innerHTML = "";
  }, res, function(res) {
    overlay_output.innerHTML = res;
    overlay_output.scrollTop=overlay_output.scrollHeight;
  }, 60000); /*add disk 60s timeout*/
}
function add_disk(host, uuid) {
  const form = document.getElementById('adddisk_form');
  const goldlst = document.getElementById('gold_list');
  const devlst = document.getElementById('dev_list');
  getjson('GET', `/tpl/device/${host}`, function(res) {
    var devs = JSON.parse(res);
    devlst.innerHTML = gen_dev_list(devs, 'disk');
  });
  getjson('GET', `/tpl/gold/${host}`, function(res) {
    var gold = JSON.parse(res);
    goldlst.innerHTML = gen_gold_list(gold);
  }, null);
  form.addEventListener('submit', function(event) {
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    console.log(`add disk : ${res}`);
    do_add(host, uuid, res);
    showView('hostlist');
  }, { once: true });
  showView('adddisk');
}
function add_net(host, uuid) {
  const form = document.getElementById('addnet_form');
  const netlst = document.getElementById('net_list');
  getjson('GET', `/tpl/device/${host}`, function(res) {
    var devs = JSON.parse(res);
    netlst.innerHTML = gen_dev_list(devs, 'net');
  });
  form.addEventListener('submit', function(event) {
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    console.log(`add net : ${res}`);
    do_add(host, uuid, res);
    showView('hostlist');
  }, { once: true });
  showView('addnet');
}
function add_iso(host, uuid) {
  const form = document.getElementById('addiso_form');
  const isolst = document.getElementById('iso_list');
  getjson('GET', `/tpl/device/${host}`, function(res) {
    var devs = JSON.parse(res);
    isolst.innerHTML = gen_dev_list(devs, 'iso');
  });
  form.addEventListener('submit', function(event) {
    event.preventDefault(); // Prevents the default form submission
    const res = getFormJSON(form);
    console.log(`add iso : ${res}`);
    do_add(host, uuid, res);
    showView('hostlist');
  }, { once: true });
  showView('addiso');
}
/* create vm add new meta key/value */
function set_name(r) {
  var i = r.parentNode.parentNode.rowIndex;
  var input = document.getElementById("table_meta_data").rows[i].cells[1].getElementsByTagName('input')
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
  c_name.innerHTML = '<input type="text"/ placeholder="name" onChange="set_name(this)">';
  c_value.innerHTML = '<input type="text" placeholder="value" required>';
  del_btn.innerHTML = '<input type="button" value="Remove" onclick="del_meta(this)"/>';
}
/* include html */
function includeHTML() {
  var z, i, elmnt, file, xhttp;
  /* Loop through a collection of all HTML elements: */
  z = document.getElementsByTagName("*");
  for (i = 0; i < z.length; i++) {
    elmnt = z[i];
    /*search for elements with a certain atrribute:*/
    file = elmnt.getAttribute("w3-include-html");
    if (file) {
      /* Make an HTTP request using the attribute value as the file name: */
      xhttp = new XMLHttpRequest();
      xhttp.onreadystatechange = function() {
        if (this.readyState == 4) {
          if (this.status == 200) {elmnt.innerHTML = this.responseText;}
          if (this.status == 404) {elmnt.innerHTML = "Page not found.";}
          /* Remove the attribute, and call this function once more: */
          elmnt.removeAttribute("w3-include-html");
          includeHTML();
        }
      }
      xhttp.open("GET", file, true);
      xhttp.send();
      /* Exit the function: */
      return;
    }
  }
}
/* ------------------------- */
window.onload = function() {
  includeHTML();
  getjson('GET', '/tpl/host', function (res) {
    config.g_hosts = JSON.parse(res);
    var mainMenu = "";
    for(var n = 0; n < config.g_hosts.length; n++) {
      mainMenu += `<a href='#' class='nav_link sublink' onclick='on_menu_host(config.g_hosts, ${n})'><i class="fa fa-desktop"></i><span>${config.g_hosts[n].name}</span></a>`;
    }
    document.getElementById("sidebar").innerHTML = mainMenu;
  });
}
/* ------------------------- */
function getTheme() {
  return localStorage.getItem('theme') || 'light';
}
function saveTheme(theme) {
  localStorage.setItem('theme', theme);
}
/* ------------------------- */
