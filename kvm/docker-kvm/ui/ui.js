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
    table += `<a href='#' onclick='start("${host}", "${item.uuid}")'>Start</a>&nbsp;`
    table += `<a href='#' onclick='stop("${host}", "${item.uuid}")'>Stop</a>&nbsp;`
    table += `<a href='#' onclick='undefine("${host}", "${item.uuid}")'>Rm</a>&nbsp;`
    table += `<a href='#' onclick='add_device("${host}", "${item.uuid}")'>Add</a>&nbsp;`
    table += `<a href='#' onclick='display("${host}", "${item.uuid}")'>VNC</a>`
    table += "</td></tr>";
  });
  table += "</table>";
  return table;
}
function show_host(host) {
  var table = "<table><tr>";
  for(var key in host) {
    table += `<th>${key}</th>`;
  }
  table += "<th>Actions</th></tr><tr>";
  for(var key in host) {
    table += `<td>${host[key]}</td>`;
  }
  table += `<td><a href='#' onclick='create_vm("${host.name}", "${host.arch}")'>Create VM</a></td></tr></table>`;
  return table;
}
var g_menu = [ { "name" : "About", "url" : "#", "submenu" : [ { "name" : "about", "url" : "about.html" } ] } ]
var g_hosts='';
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
function getjson(method, url, callback, res) {
  var sendObject = null;
  if(null !== res && typeof res !== 'undefined') {
    sendObject = JSON.stringify(res);
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
function on_menu_host(host, n) {
  //clear
  document.getElementById("host").innerHTML = ''
  document.getElementById("vms").innerHTML = ''
  //display
  document.getElementById("host").innerHTML = show_host(host[n]);
  var name=host[n].name
  getjson('GET', `/vm/list/${name}`, function(res) {
      vms = JSON.parse(res);
      document.getElementById("vms").innerHTML = show_vms(name, vms) 
    }, null
  );
}
function create_vm(host, arch) {
  alert(`create_vm ${host} ${arch}`);
}
function add_device(host, uuid) {
  alert(`add_device ${host} ${uuid}`);
}
function start(host, uuid) {
  getjson('GET', `/vm/start/${host}/${uuid}`, function(res) {
      result = JSON.parse(res);
      if(result.result === 'OK') {
        dispok('start vm OK');
      } else {
        disperr(result.code, result.name, result.desc)
      }
    }, null
  );
}
function stop(host, uuid) {
  getjson('GET', `/vm/stop/${host}/${uuid}`, function(res) {
      result = JSON.parse(res);
      if(result.result === 'OK') {
        dispok(' stop vm OK');
      } else {
        disperr(result.code, result.name, result.desc)
      }
    }, null
  );
}
function undefine(host, uuid) {
  getjson('GET', `/vm/delete/${host}/${uuid}`, function(res) {
      result = JSON.parse(res);
      if(result.result === 'OK') {
        dispok('undefine vm OK');
        // refresh vms display
        getjson('GET', `/vm/list/${host}`, function(res) {
            vms = JSON.parse(res);
            document.getElementById("vms").innerHTML = show_vms(name, vms)
          }, null
        );
      } else {
        disperr(result.code, result.name, result.desc)
      }
    }, null
  );
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
    }, null
  );
}
