import libvirt

class VMManager:
    def __init__(self, uri):
        self.conn = libvirt.open(uri)

    # Python3 f-string(formatted string literals)
    def create_vm(self, vm_name, uuid, memory=512, vcpu=1, capacity=8, image_path='.'):
        xml_config = f"""      
                <domain type='qemu'>
                {vmname}
                </domain>"""
        try:
            self.conn.createXML(xml_config, 0)
            with open('vm_info.txt', 'a') as f:
                f.write(f'{uuid},{vm_name}\n')
            return f"VM {vm_name} created successfully"
        except libvirt.libvirtError as e:
            return str(e)

    def delete_vm(self, vm_name):
        try:
            dom = self.conn.lookupByName(vm_name)
            dom.destroy()  
            dom.undefine()  
            # Delete vm from log
            with open("vm_info.txt", "r") as f:
              logs = f.readlines()
            with open("vm_info.txt", "w") as f:
              for line in logs:
                if vm_name not in line:
                  f.write(line)
            return f"VM {vm_name} deleted successfully"
        except libvirt.libvirtError as e:
            return str(e)

    def start_vm(self, vm_name):
        try:
            dom = self.conn.lookupByName(vm_name)
            dom.create()
            return f"VM {vm_name} started successfully"
        except libvirt.libvirtError as e:
            return str(e)

    def stop_vm(self, vm_name):
        try:
            dom = self.conn.lookupByName(vm_name)
            dom.shutdown()
            return f"VM {vm_name} stopped successfully"
        except libvirt.libvirtError as e:
            return str(e)


from flask import request, jsonify
@app.route('/start_vm', methods=['POST'])
def start_vm():
    data = request.json
    user_id = data.get('user_id')
    vm_name = data.get('vm_name')

    if not verify_user(user_id):
        return jsonify({"error": "Invalid user"}), 403

    result = vm_manager.start_vm(vm_name)
    return jsonify({"result": result})

@app.route('/create_vm', methods=['POST'])
def create_vm():
    data = request.json
    user_id = data.get('user_id')
    vm_name = data.get('vm_name') 
    memory = data.get('memory') # RAM in MB
    vcpu = data.get('vcpu') # No of virtual CPUs
    capacity = data.get('capacity') # disk size in GB
    image_path = data.get('img-path') # path of the bootable image

    if not verify_user(user_id):
        return jsonify({"error": "Invalid user"}), 403

    result = vm_manager.create_vm(vm_name, user_id, memory, vcpu, capacity, image_path)
    return jsonify({"result": result})

