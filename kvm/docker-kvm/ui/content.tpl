<div id="overlay"><pre id="overlay_output"></pre><div id="overlay_text">Wait......</div></div>
<div id="alert" class="tabContent"></div>
<div id="allvms" class="tabContent">
  <center><h1>ALL VMS (<span id="dbvms-total"></span>)</h1></center>
  <!-- <button onclick='overlayon()'>test overlay</button> -->
  <!-- background-image: url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 8 8" fill="none" stroke="black"><path d="M7.5 3L4 6 .5 3"/></svg>'); -->
  <div class="machine-container">
  <div class="vms-container" id="dbvms"></div>
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
<div id="display" class="tabContent">
  <embed id="display" width="800" height="600" src="" type="text/html"/>
</div>
<!-- ############## -->
<div id="vmuimail" class="tabContent">
  <div class="form-wrapper">
    <div class="form-wrapper-header">
      <h2>VM Admin UI</h2>
      <button title="Close" class="close" onclick="showView('hostlist')"><h2>&times;</h2></button>
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
      <button title="Close" class="close" onclick="showView('hostlist')"><h2>&times;</h2></button>
    </div>
    <form id="vmui_form">
      <label>Expire:
      <div class="group">
        <input type="date" name="date" required/>
        <input type="time" name="time" value="23:59" step="1" required/>
      </div></label>
      <input type="reset" value="Reset"/>
      <input type="submit" value="Submit"/>
    </form>
  </div>
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
      <input type="reset" value="Reset"/>
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
      <input type="reset" value="Reset"/>
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
      <input type="reset" value="Reset"/>
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
      <label>CPU:<div class="group">
        <input style="width: 20%;" type="number" name="vm_vcpus" id="vcpu_num" value="2" min="1" max="16" oninput="vcpu_rge.value=this.value" />
        <input type="range" id="vcpu_rge" value="2" min="1" max="16" oninput="vcpu_num.value=this.value"/>
      </div></label>
      <label>MEM(MB):<div class="group">
        <input style="width: 20%;" type="number" name="vm_ram_mb" id="vmem_num"  value="2048" min="1024" max="16384" step="1024" oninput="vmem_rge.value=this.value"/>
        <input type="range" id="vmem_rge"  value="2048" min="1024" max="16384" step="1024" oninput="vmem_num.value=this.value"/>
      </div></label>
      <label>desc<textarea rows="3" maxlength="100" name="vm_desc" placeholder="vm desc here..." required></textarea></label>
      <fieldset>
        <legend>MetaData</legend>
        <label>Ipaddr*<input type="text" name="vm_ip" id="vm_ip" placeholder="e.g. 192.168.168.2/24" required pattern="^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?).){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)/([1-9]{1}|1[0-9]{1}|2[0-9]{1}|3[0-2]{1})$"/></label>
        <label>Gateway<input type="text" name="vm_gw" id="vm_gw" placeholder="e.g. 192.168.168.1" pattern="^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?).){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$"/></label>
        <table id="table_meta_data"></table>
        <input type="button" value="AddField" onclick="add_meta()"/>
      </fieldset>
      <br>
      <input type="reset" value="Reset"/>
      <input type="submit" value="Submit"/>
    </form>
  </div>
</div>
</div>
