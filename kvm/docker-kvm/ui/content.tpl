<div id="overlay"><pre id="overlay_output"></pre><div id="overlay_text">Wait......</div></div>
<!-- ############## -->
<dialog id="alert" closedby="any"></dialog>
<!-- ############## -->
<div id="manage_vm" class="tabContent">
  <div class="machine-container">
    <div class="vms-container" id="vm_info"></div>
    </div>
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
<div id="vmuimail" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>VM Admin UI</h2>
      <button title="Close" class="close" onclick="showView('manage_vm')"><h2>&times;</h2></button>
    </div>
    <form onsubmit="return setAction(this);" method="post" enctype="text/plain">
      <a style="color: var(--green-color);" target="_blank" id="url"/>ACCESS VM</a>
      <label>Expire:<input readonly type="text" id="expire" name="expire"/></label>
      <label>Token:<input readonly type="text" id="token" name="token"/></label>
      <fieldset>
        <legend>VM ControlUI</legend>
        <label>Mail:<input type="email" id="email" placeholder="Enter your email" required/></label>
        <input type="submit" value="SendMail">
      </fieldset>
    </form>
  </div>
</div>
<div id="vmui" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Input ExpireTime</h2>
      <button title="Close" class="close" onclick="showView('manage_vm')"><h2>&times;</h2></button>
    </div>
    <form onSubmit="return on_vmui(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>Expire:<input type="date" name="date" required/></label>
      <input type="reset" value="Reset"/>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="changecdrom" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Change ISO</h2>
      <button title="Close" class="close" onclick="showView('manage_vm')"><h2>&times;</h2></button>
    </div>
    <form onSubmit="return on_changeiso(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>ISO:<select name="isoname" id="isoname_list"></select></label>
      <input type="reset" value="Reset"/>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="addcdrom" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Add CDROM</h2>
      <button title="Close" class="close" onclick="showView('manage_vm')"><h2>&times;</h2></button>
    </div>
    <form id="addcdrom_form" onSubmit="return on_add(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>CDROM:<select name="device" id="cdrom_list" onchange="select_change(this)"></select></label>
      <table name="meta_data"></table><datalist name="help" id="addcdrom_mdlist"></datalist><div name='help'></div>
      <input type="button" value="AddField" onclick="add_meta(this)"/>
      <input type="reset" value="Reset"/>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="addnet" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Add Network</h2>
      <button title="Close" class="close" onclick="showView('manage_vm')"><h2>&times;</h2></button>
    </div>
    <form id="addnet_form" onSubmit="return on_add(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>Network:<select name="device" id="net_list" onchange="select_change(this)"></select></label>
      <table name="meta_data"></table><datalist name="help" id="addnet_mdlist"></datalist><div name='help'></div>
      <input type="button" value="AddField" onclick="add_meta(this)"/>
      <input type="reset" value="Reset"/>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="adddisk" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Add DISK</h2>
      <button title="Close" class="close" onclick="showView('manage_vm')"><h2>&times;</h2></button>
    </div>
    <form id="adddisk_form" onSubmit="return on_add(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>Gold:<select name="gold" id="gold_list" onchange="gold_change(this)"></select></label>
      <label>Disk:<select name="device" id="dev_list" onchange="select_change(this)"></select></label>
      <label>Size(GB):<input type="number" name="size" id="gold_size" min="1" max="2048"/></label>
      <table name="meta_data"></table><datalist name="help" id="adddisk_mdlist"></datalist><div name='help'></div>
      <input type="button" value="AddField" onclick="add_meta(this)"/>
      <input type="reset" value="Reset"/>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="modifyvcpus" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Modify Vcpus</h2>
      <button title="Close" class="close" onclick="showView('manage_vm')"><h2>&times;</h2></button>
    </div>
    <form onSubmit="return on_modifyvcpus(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>CPU:<div class="group">
        <input style="width: 20%;" type="number" name="vm_vcpus" id="vcpu_num" value="2" min="1" max="16" oninput="vcpu_rge.value=this.value" />
        <input type="range" id="vcpu_rge" value="2" min="1" max="16" oninput="vcpu_num.value=this.value"/>
      </div></label>
      <input type="reset" value="Reset"/>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="modifymemory" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Modify Memory</h2>
      <button title="Close" class="close" onclick="showView('manage_vm')"><h2>&times;</h2></button>
    </div>
    <form onSubmit="return on_modifymemory(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>MEM(MB):<div class="group">
        <input style="width: 20%;" type="number" name="vm_ram_mb" id="vmem_num" value="2048" min="1024" max="32768" step="1024" oninput="vmem_rge.value=this.value"/>
        <input type="range" id="vmem_rge" value="2048" min="1024" max="32768" step="1024" oninput="vmem_num.value=this.value"/>
      </div></label>
      <input type="reset" value="Reset"/>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="modifydesc" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Modify Description</h2>
      <button title="Close" class="close" onclick="showView('manage_vm')"><h2>&times;</h2></button>
    </div>
    <form onSubmit="return on_modifydesc(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <label>desc<textarea rows="3" maxlength="100" name="vm_desc" placeholder="vm desc here..." required></textarea></label>
      <input type="reset" value="Reset"/>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
<!-- ############## -->
<div id="createvm" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>Create VM</h2>
      <button title="Close" class="close" onclick="showView('hostlist')"><h2>&times;</h2></button>
    </div>
    <form id="createvm_form" onSubmit="return on_createvm(this)" onkeydown="if(event.keyCode === 13){return false;}">
      <fieldset><legend>Meta Server Type</legend>
      <label><input type="checkbox" name="vm_meta_enum" value="NOCLOUD">NOCLOUD</label>
      </fieldset>
      <fieldset><legend>Device</legend>
      <label><input type="checkbox" name="vm_rng" value="no">Remove RNG Random Device</label>
      </fieldset>
      <label>CPU:<div class="group">
        <input style="width: 20%;" type="number" name="vm_vcpus" id="vcpu_num" value="2" min="1" max="16" oninput="vcpu_rge.value=this.value" />
        <input type="range" id="vcpu_rge" value="2" min="1" max="16" oninput="vcpu_num.value=this.value"/>
      </div></label>
      <label>MEM(MB):<div class="group">
        <input style="width: 20%;" type="number" name="vm_ram_mb" id="vmem_num" value="2048" min="1024" max="32768" step="1024" oninput="vmem_rge.value=this.value"/>
        <input type="range" id="vmem_rge" value="2048" min="1024" max="32768" step="1024" oninput="vmem_num.value=this.value"/>
      </div></label>
      <label>desc<textarea rows="3" maxlength="100" name="vm_desc" placeholder="vm desc here..." required></textarea></label>
      <label>IPaddr*<input type="text" name="vm_ipaddr" id="vm_ip" placeholder="e.g. 192.168.168.2/24" required pattern="^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?).){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/([1-9]{1}|1[0-9]{1}|2[0-9]{1}|3[0-2]{1})$"/></label>
      <label>Gateway<input type="text" name="vm_gateway" id="vm_gw" placeholder="e.g. 192.168.168.1" pattern="^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?).){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"/></label>
      <table name="meta_data"></table><datalist name="help" id="createvm_mdlist"></datalist><div name='help'></div>
      <input type="button" value="AddField" onclick="add_meta(this)"/>
      <input type="reset" value="Reset"/>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
