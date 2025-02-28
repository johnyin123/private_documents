<div id="about" class="tabContent" style="display:block;">
  <!-- UI DEMO START -->
  <center><h1>DEMO index page</h1></center>
  <button onclick='overlayon()'>test overlay</button>
  <div class="machine-container">
    <div class="host-container">
      <div class="host-wrapper">
        <div class="host-wrapper-header"><h2>KVM HOST</h2><div><button title='Create VM' onclick='showView("createvm")'><i class="fa fa-plus"></i></button></div></div>
        <table><tr><th width="20%">active</th><td>0</td></tr><tr><th width="20%">arch</th><td>x86_64</td></tr><tr><th width="20%">desc</th><td>null</td></tr><tr><th width="20%">inactive</th><td>0</td></tr><tr><th width="20%">ipaddr</th><td>192.168.168.1/24</td></tr><tr><th width="20%">name</th><td>host01</td></tr><tr><th width="20%">sshport</th><td>60022</td></tr><tr><th width="20%">tpl</th><td>newvm.vnc.tpl</td></tr><tr><th width="20%">url</th><td>qemu+tls://192.168.168.1/system</td></tr></table>
      </div>
    </div>
    <div class="vms-container">
      <div class="vms-wrapper">
        <div class="vms-wrapper-header"><h2>KVM GUEST</h2><div><button title='VNC'><i class="fa fa-television"></i></button><button title='Start'><i class="fa fa-play"></i></button><button title='Stop'><i class="fa fa-power-off"></i></button><button title='ForceStop'><i class="fa fa-plug"></i></button><button title='Undefine'><i class="fa fa-times"></i></button><button title='Add ISO' onclick='showView("addiso")'><i class="fa fa-plus"></i></button><button title='Add NET' onclick='showView("addnet")'><i class="fa fa-plus"></i></button><button title='Add DISK' onclick='showView("adddisk")'><i class="fa fa-plus"></i></button></div></div>
        <table><tr><th width="20%">cputime</th><td>0</td></tr><tr><th width="20%">create</th><td>20250219125843</td></tr><tr><th width="20%">curcpu</th><td>2</td></tr><tr><th width="20%">curmem</th><td>2097152</td></tr><tr><th width="20%">desc</th><td></td></tr><tr><th width="20%">gateway</th><td>null</td></tr><tr><th width="20%">ipaddr</th><td>192.168.168.2/32</td></tr><tr><th width="20%">maxmem</th><td>16777216</td></tr><tr><th width="20%">state</th><td>5</td></tr><tr><th width="20%">uuid</th><td>7cb79a8a-5d9f-4a53-9705-6b37f6085c11</td></tr><tr><th width="20%">vcpus</th><td>8</td></tr></table>
      </div>
      <div class="vms-wrapper">
        <div class="vms-wrapper-header"><h2>KVM GUEST</h2><div><button title='VNC'><i class="fa fa-television"></i></button><button title='Start'><i class="fa fa-play"></i></button><button title='Stop'><i class="fa fa-power-off"></i></button><button title='ForceStop'><i class="fa fa-plug"></i></button><button title='Undefine'><i class="fa fa-times"></i></button><button title='Add ISO' onclick='showView("addiso")'><i class="fa fa-plus"></i></button><button title='Add NET' onclick='showView("addnet")'><i class="fa fa-plus"></i></button><button title='Add DISK' onclick='showView("adddisk")'><i class="fa fa-plus"></i></button></div></div>
        <table><tr><th width="20%">cputime</th><td>0</td></tr><tr><th width="20%">create</th><td>20250219125843</td></tr><tr><th width="20%">curcpu</th><td>2</td></tr><tr><th width="20%">curmem</th><td>2097152</td></tr><tr><th width="20%">desc</th><td></td></tr><tr><th width="20%">gateway</th><td>null</td></tr><tr><th width="20%">ipaddr</th><td>192.168.168.2/22</td></tr><tr><th width="20%">maxmem</th><td>16777216</td></tr><tr><th width="20%">state</th><td>5</td></tr><tr><th width="20%">uuid</th><td>7cb79a8a-5d9f-4a53-9705-6b37f6085c11</td></tr><tr><th width="20%">vcpus</th><td>8</td></tr></table>
      </div>
    </div>
  </div>
  <!-- UI DEMO END -->
</div>
<!-- ############## -->
<div id="hostlist" class="tabContent">
  <div class="machine-container">
    <div class="host-container" id="host"></div>
    <div class="vms-container" id="vms"></div>
  </div>
</div>
<!-- ############## -->
<div id="display" class="tabContent">
  <embed id="display" width="800" height="600" src="" type="text/html"/>
</div>
<!-- ############## -->
<div id="addiso" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>AddISO</h2>
      <button title="Close" class="close" onclick="showView('hostlist')"><h2>&times;</h2></button>
    </div>
    <form id="addiso_form">
      <label>ISO:<select name="device" id="iso_list"></select></label>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="addnet" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>AddNetwork</h2>
      <button title="Close" class="close" onclick="showView('hostlist')"><h2>&times;</h2></button>
    </div>
    <form id="addnet_form">
      <label>Network:<select name="device" id="net_list"></select></label>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="adddisk" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>AddDISK</h2>
      <button title="Close" class="close" onclick="showView('hostlist')"><h2>&times;</h2></button>
    </div>
    <form id="adddisk_form">
      <label>Gold:<select name="gold" id="gold_list"></select></label>
      <label>Disk:<select name="device" id="dev_list"></select></label>
      <label>Size(GB):<input type="number" name="size" value="10" min="1" max="1024"/></label>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="createvm" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>CreateVM</h2>
      <button title="Close" class="close" onclick="showView('hostlist')"><h2>&times;</h2></button>
    </div>
    <form id="createvm_form">
      <label>cpu<input type="number" name="vm_vcpus" value="2" min="1" max="16"/></label>
      <label>mem(MB)<input type="number" name="vm_ram_mb" value="2048" min="1024" max="16384" step="1024"/></label>
      <label>desc<textarea rows="3" name="vm_desc" placeholder="vm desc here..."></textarea></label>
      <label>ip*<input type="text" name="vm_ip" placeholder="ipaddr like 192.168.168.2/24" required/></label>
      <label>gw<input type="text" name="vm_gw" placeholder="gateway like 192.168.168.1"/></label>
      <table id="table_meta_data"></table>
      <input type="button" value="AddField" onclick="add_meta()"/>
      <input type="reset" value="Reset"/>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
</div>
