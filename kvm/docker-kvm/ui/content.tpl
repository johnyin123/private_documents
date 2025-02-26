<div id="about" class="tabContent">
  <!-- UI DEMO START -->
  <section>
      <div class="form-wrapper-header"><h2>KVM HOST</h2><div><button title='Create VM' onclick='create_vm("host01", "x86_64")'>Create VM</button></div></div><br>
    <div class="row">
      <div class="column form-wrapper">
        <div class="form-wrapper-header"><h2>KVM GUEST</h2><div><button title='VNC'><i class="fa fa-television"></i></button><button title='Start'><i class="fa fa-play"></i></button><button title='Stop'><i class="fa fa-power-off"></i></button><button title='ForceStop'><i class="fa fa-plug"></i></button><button title='Undefine'><i class="fa fa-times"></i></button><button title='Add ISO' onclick='showView("addiso")'><i class="fa fa-plus"></i></button><button title='Add NET' onclick='showView("addnet")'><i class="fa fa-plus"></i></button><button title='Add DISK' onclick='showView("adddisk")'><i class="fa fa-plus"></i></button></div></div><br>
        <table class="scrolldown"><tr><th width="20%">cputime</th><td>0</td></tr><tr><th width="20%">create</th><td>20250219125843</td></tr><tr><th width="20%">curcpu</th><td>2</td></tr><tr><th width="20%">curmem</th><td>2097152</td></tr><tr><th width="20%">desc</th><td></td></tr><tr><th width="20%">gateway</th><td>null</td></tr><tr><th width="20%">ipaddr</th><td>192.168.168.2/3222</td></tr><tr><th width="20%">maxmem</th><td>16777216</td></tr><tr><th width="20%">state</th><td>5</td></tr><tr><th width="20%">uuid</th><td>7cb79a8a-5d9f-4a53-9705-6b37f6085c11</td></tr><tr><th width="20%">vcpus</th><td>8</td></tr><tr></table>
      </div>
      <div class="column form-wrapper">
        <div class="form-wrapper-header"><h2>KVM GUEST</h2><div><button title='VNC'><i class="fa fa-television"></i></button><button title='Start'><i class="fa fa-play"></i></button><button title='Stop'><i class="fa fa-power-off"></i></button><button title='ForceStop'><i class="fa fa-plug"></i></button><button title='Undefine'><i class="fa fa-times"></i></button><button title='Add ISO' onclick='showView("addiso")'><i class="fa fa-plus"></i></button><button title='Add NET' onclick='showView("addnet")'><i class="fa fa-plus"></i></button><button title='Add DISK' onclick='showView("adddisk")'><i class="fa fa-plus"></i></button></div></div><br>
        <table class="scrolldown"><tr><th width="20%">cputime</th><td>0</td></tr><tr><th width="20%">create</th><td>20250219125843</td></tr><tr><th width="20%">curcpu</th><td>2</td></tr><tr><th width="20%">curmem</th><td>2097152</td></tr><tr><th width="20%">desc</th><td></td></tr><tr><th width="20%">gateway</th><td>null</td></tr><tr><th width="20%">ipaddr</th><td>192.168.168.2/3222</td></tr><tr><th width="20%">maxmem</th><td>16777216</td></tr><tr><th width="20%">state</th><td>5</td></tr><tr><th width="20%">uuid</th><td>7cb79a8a-5d9f-4a53-9705-6b37f6085c11</td></tr><tr><th width="20%">vcpus</th><td>8</td></tr><tr></table>
      </div>
    </div>
  </section>
  <!-- UI DEMO END -->
</div>
<!-- ############## -->
<div id="hostlist" class="tabContent">
  <section>
    <div class="form-wrapper" id="host"></div>
    <hr>
    <div id="vms" class="row"></div>
  </section>
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
      <button class="close" onclick="showView('hostlist')"></button>
    </div>
    <form id="addiso_form">
      <div id="iso_list">
        <label>ISO:
          <select name="device">
            <option value="centos_x86_64">centos8 x86_64</option>
          </select>
        </label>
      </div>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="addnet" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>AddNetwork</h2>
      <button class="close" onclick="showView('hostlist')"></button>
    </div>
    <form id="addnet_form">
      <div id="net_list">
        <label>Network:
          <select name="device">
            <option value="br-ext">bridge netnwork</option>
          </select>
        </label>
      </div>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="adddisk" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>AddDISK</h2>
      <button class="close" onclick="showView('hostlist')"></button>
    </div>
    <form id="adddisk_form">
      <div id="gold_list">
        <label>Gold:
          <select name="gold">
            <option value="" selected>数据盘</option>
            <option value="syslinux">linunx</option>
          </select>
        </label>
      </div>
      <div id="dev_list">
        <label>Disk:
          <select name="device">
            <option value="filesys">rbd disk</option>
          </select>
        </label>
      </div>
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
      <button class="close" onclick="showView('hostlist')"></button>
    </div>
    <form id="createvm_form">
      <div class="form-wrapper-input-flex">
        <div><label>cpu<input type="number" name="vm_vcpus" value="2" min="1" max="16"/></label></div>
        <div><label>mem(MB)<input type="number" name="vm_ram_mb" value="2048" min="1024" max="16384" step="1024"/></label></div>
      </div>
      <label>desc<textarea rows="3" name="vm_desc" placeholder="vm desc here..."></textarea></label>
      <div class="form-wrapper-input-flex">
        <div><label>ip*<input type="text" name="vm_ip" placeholder="ipaddr like 192.168.168.2/24" required/></label></div>
        <div><label>gw<input type="text" name="vm_gw" placeholder="gateway like 192.168.168.1"/></label></div>
      </div>
      <div id="meta_data"><table id="table_meta_data"></table></div>
      <input type="button" value="AddField" onclick="add_meta()"/>
      <input type="reset" value="Reset"/>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
