<div id="overlay"><pre id="overlay_output"></pre><div id="overlay_text">Wait......</div></div>
<!-- ############## -->
<dialog id="alert" closedby="any"></dialog>
<!-- ############## -->
<div id="conf_host" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Add KVM HOST</h2>
      <button title="Close" onclick="showView('configuration')">&times;</button>
    </div>
    <form id="addhost_form" onSubmit="return on_conf_addhost(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>Name*<input type="text" autocomplete="off" name="name" pattern="[a-zA-Z0-9._-]+" required/></label>
      <label>Arch*<select name="arch" required>
        <option value="x86_64" selected>x86_64</option>
        <option value="aarch64">ARM64</option>
      </select></label>
      <label>Domain TPL*<select name="tpl" id="conf_domains_tpl" required></select></label>
      <label>SSH USER/IP/PORT*
      <div class="flex-group">
        <input style="width: 30%;" type="text" name="sshuser" placeholder="ssh user" pattern="[a-zA-Z0-9._-]+" required/>@
        <input type="text" name="ipaddr" placeholder="ssh ip address" pattern="^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?).){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$" required/>:
        <input style="width: 30%;" type="number" name="sshport" title="ssh port" value="22" required/>
      </div></label>
      <datalist id="qemu_url_list">
        <option value="qemu+tls://host/system">
        <option value="qemu+ssh://user@host:port/system">
        <option value="qemu+ssh://user@host:port/system?socket=/run/libvirt/libvirt-sock">
      </datalist>
      <label>QEMU URL:<input type="text" name="url" list="qemu_url_list" autocomplete="off" required/></label>
      <fieldset><legend>Device</legend>
        <div class="flex-group" id="conf_devices_tpl"></div>
      </fieldset>
      <div class="flex-group">
        <input type="reset" value="Reset"/>
        <input type="button" value="List" onclick="on_conf_listhost(this)"/>
        <input type="submit" value="Submit"/>
      </div>
    </form>
    <div class="vms-container" id="conf_host_list"></div>
  </div>
</div>
<!-- ############## -->
<div id="conf_iso" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Add TPL ISO</h2>
      <button title="Close" onclick="showView('configuration')">&times;</button>
    </div>
    <form id="addiso_form" onSubmit="return on_conf_addiso(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>Name*<input type="text" autocomplete="off" name="name" placeholder="uniq name" pattern="[a-zA-Z0-9._-]+" required/></label>
      <label>URI*<div class="flex-group"><input type="text" name="uri" placeholder="uri(unix path)" pattern="^(/[a-zA-Z0-9._\-]+/?)*$" required/><input style="width: 20%;" type="button" value="ISO Server" onclick="disp_iso_server(this)"/></div></label>
      <label>Desc*<textarea rows="3" maxlength="100" name="desc" placeholder="desc here..." required></textarea></label>
      <div class="flex-group">
        <input type="reset" value="Reset"/>
        <input type="button" value="List" onclick="on_conf_listiso(this)"/>
        <input type="submit" value="Submit"/>
      </div>
    </form>
    <div class="vms-container" id="conf_iso_list"></div>
  </div>
</div>
<!-- ############## -->
<div id="conf_gold" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Add TPL GOLD</h2>
      <button title="Close" onclick="showView('configuration')">&times;</button>
    </div>
    <form id="addgold_form"  onSubmit="return on_conf_addgold(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>Name*<input type="text" autocomplete="off" name="name" placeholder="uniq name" pattern="[a-zA-Z0-9._-]+" required/></label>
      <label>Arch*<select name="arch" required>
        <option value="x86_64" selected>x86_64</option>
        <option value="aarch64">ARM64</option>
      </select></label>
      <label>URI*<div class="flex-group"><input type="text" name="uri" placeholder="uri(unix path)" pattern="^(/[a-zA-Z0-9._\-]+/?)*$" required/><input style="width: 20%;" type="button" value="Gold Server" onclick="disp_gold_server(this)"/></div></label>
      <label>Min Size(GiB)*<input type="number" name="size" value="1" min="1" max="2048" required/></label>
      <label>Desc*<textarea rows="3" maxlength="100" name="desc" placeholder="desc here..." required></textarea></label>
      <div class="flex-group">
        <input type="reset" value="Reset"/>
        <input type="button" value="List" onclick="on_conf_listgold(this)"/>
        <input type="submit" value="Submit"/>
      </div>
    </form>
    <div class="vms-container" id="conf_gold_list"></div>
  </div>
</div>
<!-- ############## -->
<div id="conf_restore" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Restore Config</h2>
      <button title="Close" onclick="showView('configuration')">&times;</button>
    </div>
    <form onSubmit="return on_conf_restore(this)" enctype="multipart/form-data" onkeydown="if(event.keyCode === 13){return false;}">
      <input type="file" name="file" required>
      <div class="flex-group">
        <input type="reset" value="Reset"/><input type="submit" value="Submit"/>
      </div>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="configuration" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Configurations</h2>
      <button title="Close" onclick="showView('hostlist');flush_sidebar('ALL VMS');">&times;</button>
    </div>
    <form>
      <fieldset><legend>Config</legend>
        <div class="flex-group" id="config"></div>
      </fieldset>
      <fieldset><legend>ssh pubkey</legend>
        <div class="flex-group" id="ssh_pubkey"></div>
      </fieldset>
      </br>
      <div class="flex-group">
        <input type="button" value="FLUSH CACHE" onclick="load_conf(`?${Date.now()}`)"/>
        <input type="button" value="CONF HOST" onclick="show_conf_host_view()"/>
        <input type="button" value="CONF GOLD" onclick="show_conf_gold_view()"/>
        <input type="button" value="CONF ISO" onclick="show_conf_iso_view()"/>
        <input type="button" value="Backup" onclick="on_conf_backup()"/>
        <input type="button" value="Restore" onclick="showView('conf_restore')">
      </div>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="manage_vm" class="tabContent">
  <div class="machine-container">
    <div class="vms-container" id="vm_info"></div>
    <div class="vms-container" id="snap_info"></div>
  </div>
</div>
<!-- ############## -->
<div id="hostlist" class="tabContent">
  <div class="machine-container">
    <div class="host-container" id="host"></div>
    <div class="vms-container" id="vms"></div>
  </div>
</div>
<!-- ############## -->
<div id="modifymdconfig" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Modify Metadata</h2>
      <button title="Close" onclick="showView('manage_vm')">&times;</button>
    </div>
    <form onSubmit="return on_modifymdconfig(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <fieldset><legend>Meta</legend>
        <div class="flex-group" id="div-metadata"></div>
      </fieldset>
      <div class="flex-group">
        <input type="reset" value="Reset"/>
        <input type="submit" value="Submit"/>
      </div>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="vmuimail" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Control Panel Info</h2>
      <button title="Close" onclick="showView('manage_vm')">&times;</button>
    </div>
    <form onsubmit="return setAction(this);" method="post" enctype="text/plain">
      <table>
      <tr>
        <th class="truncate">URL</th>
        <td colspan="3" class="truncate"><a target="_blank" href='#' title="Open Control Panel" id="url"/></a></td>
      </tr>
      </table>
      <br/>
      <fieldset><legend>Mail Content</legend>
        <label>Expire:<input readonly type="text" id="expire" name="expire"/></label>
        <label>Token:<input readonly type="text" id="token" name="token"/></label>
        <label>EMail*:<input type="email" id="email" autocomplete="off" placeholder="Enter your email" required/></label>
      </fieldset>
      <br/>
      <input type="submit" value="SendMail">
    </form>
  </div>
</div>
<div id="vmui" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Input ExpireTime</h2>
      <button title="Close" onclick="showView('manage_vm')">&times;</button>
    </div>
    <form onSubmit="return on_vmui(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>Expire*:<input type="date" name="date" required/><!--onclick="this.showPicker();"--></label>
      <div class="flex-group">
        <input type="reset" value="Reset"/>
        <input type="submit" value="Submit"/>
      </div>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="changecdrom" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Change ISO</h2>
      <button title="Close" onclick="showView('manage_vm')">&times;</button>
    </div>
    <form onSubmit="return on_changeiso(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>ISO:<select name="isoname" id="isoname_list" required></select></label>
      <div class="flex-group">
        <input type="reset" value="Reset"/>
        <input type="submit" value="Submit"/>
      </div>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="addcdrom" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Add CDROM</h2>
      <button title="Close" onclick="showView('manage_vm')">&times;</button>
    </div>
    <form id="addcdrom_form" onSubmit="return on_add(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <div class="flex-group">
        <label>CDROM:<select name="device" id="cdrom_list" onchange="select_change(this)" required></select></label>
        <label>BUS:<select name="vm_disk_bus" title="Bus type" required>
          <option value="sata" selected>sata</option>
          <option value="ide">ide</option>
          <option value="scsi">scsi</option>
        </select></label>
      </div>
      <table name="meta_data"></table><datalist name="help" id="addcdrom_mdlist"></datalist><div name='help'></div>
      <div class="flex-group">
        <input type="button" value="AddField" onclick="add_meta(this)"/>
        <input type="reset" value="Reset"/>
        <input type="submit" value="Submit"/>
      </div>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="addnet" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Add Network</h2>
      <button title="Close" onclick="showView('manage_vm')">&times;</button>
    </div>
    <form id="addnet_form" onSubmit="return on_add(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <div class="flex-group">
        <label>Network:<select name="device" id="net_list" onchange="select_change(this)" required></select></label>
        <label>Model:<select name="vm_net_model" title="netcard model" required>
          <option value="virtio" selected>virtio</option>
          <option value="e1000">e1000</option>
          <option value="rtl8139">rtl8139</option>
        </select></label>
      </div>
      <table name="meta_data"></table><datalist name="help" id="addnet_mdlist"></datalist><div name='help'></div>
      <div class="flex-group">
        <input type="button" value="AddField" onclick="add_meta(this)"/>
        <input type="reset" value="Reset"/>
        <input type="submit" value="Submit"/>
      </div>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="adddisk" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Add DISK</h2>
      <button title="Close" onclick="showView('manage_vm')">&times;</button>
    </div>
    <form id="adddisk_form" onSubmit="return on_add(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <div class="flex-group">
        <label>Disk:<select name="device" id="dev_list" onchange="select_change(this)" required></select></label>
        <label>Size(GiB)*:<input type="number" name="size" id="gold_size" min="1" max="2048" required/></label>
      </div>
      <div class="flex-group">
        <label>Gold:<select name="gold" id="gold_list" onchange="gold_change(this)"></select></label>
        <label>BUS:<select name="vm_disk_bus" title="Bus type" required>
          <option value="virtio" selected>virtio</option>
          <option value="ide">ide</option>
          <option value="scsi">scsi</option>
          <option value="sata">sata</option>
        </select></label>
      </div>
      <table name="meta_data"></table><datalist name="help" id="adddisk_mdlist"></datalist><div name='help'></div>
      <div class="flex-group">
        <input type="button" value="AddField" onclick="add_meta(this)"/>
        <input type="reset" value="Reset"/>
        <input type="submit" value="Submit"/>
      </div>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="modifyvcpus" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Modify Vcpus</h2>
      <button title="Close" onclick="showView('manage_vm')">&times;</button>
    </div>
    <form onSubmit="return on_modifyvcpus(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>CPU:<div class="flex-group">
        <input style="width: 20%;" type="number" name="vm_vcpus" id="vcpu_num_modify" value="2" min="1" max="16" oninput="vcpu_rge_modify.value=this.value" />
        <input type="range" id="vcpu_rge_modify" value="2" min="1" max="16" tabindex="-1" oninput="vcpu_num_modify.value=this.value"/>
      </div></label>
      <div class="flex-group">
        <input type="reset" value="Reset"/>
        <input type="submit" value="Submit"/>
      </div>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="modifymemory" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Modify Memory</h2>
      <button title="Close" onclick="showView('manage_vm')">&times;</button>
    </div>
    <form onSubmit="return on_modifymemory(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>MEM(MB):<div class="flex-group">
        <input style="width: 20%;" type="number" name="vm_ram_mb" id="vmem_num_modify" value="2048" min="1024" max="32768" step="1024" oninput="vmem_rge_modify.value=this.value"/>
        <input type="range" id="vmem_rge_modify" value="2048" min="1024" max="32768" step="1024" tabindex="-1" oninput="vmem_num_modify.value=this.value"/>
      </div></label>
      <div class="flex-group">
        <input type="reset" value="Reset"/>
        <input type="submit" value="Submit"/>
      </div>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="modifydesc" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Modify Description</h2>
      <button title="Close" onclick="showView('manage_vm')">&times;</button>
    </div>
    <form onSubmit="return on_modifydesc(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>Desc*<textarea rows="3" maxlength="100" name="vm_desc" placeholder="vm desc here..." required></textarea></label>
      <div class="flex-group">
        <input type="reset" value="Reset"/>
        <input type="submit" value="Submit"/>
      </div>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="createvm" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Create VM</h2>
      <button title="Close" onclick="showView('hostlist')">&times;</button>
    </div>
    <form id="createvm_form" onSubmit="return on_createvm(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <div class="flex-group">
        <fieldset><legend>Meta</legend>
          <label>IPaddr*<input type="text" name="vm_ipaddr" id="vm_ip" placeholder="e.g. 192.168.168.2/24" pattern="^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?).){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/([1-9]{1}|1[0-9]{1}|2[0-9]{1}|3[0-2]{1})$" autocomplete="off"/></label>
          <label>Gateway<input type="text" name="vm_gateway" id="vm_gw" placeholder="e.g. 192.168.168.1" pattern="^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?).){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$" autocomplete="off"/></label>
          <!--
          <label><input type="checkbox" name="vm_meta_enum" value="NOCLOUD">NOCLOUD</label>
          -->
          <label>Meta Server:
          <select name="vm_meta_enum">
            <option value="" selected>ISO</option>
            <option value="NOCLOUD">NoCloud</option>
          </select></label>
        </fieldset>
        <fieldset><legend>Device</legend>
          <label>CPU
            <div class="flex-group">
              <input style="width: 30%;" type="number" name="vm_vcpus" id="vcpu_num_create" value="2" min="1" max="16" oninput="vcpu_rge_create.value=this.value" />
              <input type="range" id="vcpu_rge_create" value="2" min="1" max="16" tabindex="-1" oninput="vcpu_num_create.value=this.value"/>
            </div>
          </label>
          <label>MEM(MB)
            <div class="flex-group">
              <input style="width: 30%;" type="number" name="vm_ram_mb" id="vmem_num_create" value="2048" min="1024" max="32768" step="1024" oninput="vmem_rge_create.value=this.value"/>
              <input type="range" id="vmem_rge_create" value="2048" min="1024" max="32768" step="1024" tabindex="-1" oninput="vmem_num_create.value=this.value"/>
            </div>
          </label>
          <div class="flex-group">
            <label>Graph:<select name="vm_graph" title="graph type">
              <option value="" selected>Console(only)</option> <!--disabled, if disabled, getFormJSON not contain this key-->
              <option value="vnc">VNC</option>
              <option value="spice">SPICE</option>
            </select></label>
            <label>Video Card:<select name="vm_video" title="video card" required>
              <option value="vga" selected>vga</option>
              <option value="qxl">qxl</option>
              <option value="virtio">virtio</option>
              <option value="cirrus">cirrus</option>
            </select></label>
          </div>
          <label style="font-weight: normal;"><input type="checkbox" name="vm_rng" value="no" />Remove RNG Random Device</label>
          <!--<label><input type="radio" name="vm_rng" value="yes" checked />Yes</label><label><input type="radio" name="vm_rng" value="no" />No</label>-->
        </fieldset>
      </div>
      <label>Desc*<textarea rows="3" maxlength="100" name="vm_desc" placeholder="vm desc here..." required></textarea></label>
      <table name="meta_data"></table><datalist name="help" id="createvm_mdlist"></datalist><div name='help'></div>
      <div class="flex-group">
        <input type="button" value="AddField" onclick="add_meta(this)"/>
        <input type="reset" value="Reset"/>
        <input type="submit" value="Submit"/>
      </div>
    </form>
  </div>
</div>
