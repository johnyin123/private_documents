import socket
from time import sleep
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

BUS_NAME = 'org.bluez'
AGENT_IFACE = 'org.bluez.Agent1'
AGNT_MNGR_IFACE = 'org.bluez.AgentManager1'
ADAPTER_IFACE = 'org.bluez.Adapter1'
AGENT_PATH = '/ukBaz/bluezero/agent'
AGNT_MNGR_PATH = '/org/bluez'
DEVICE_IFACE = 'org.bluez.Device1'
CAPABILITY = 'KeyboardDisplay'
my_adapter_address = '11:22:33:44:55:66'
my_device_path = '/org/bluez/hci0/dev_00_00_12_34_56_78'
dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()


class Agent(dbus.service.Object):

    @dbus.service.method(AGENT_IFACE, in_signature='o', out_signature='s')
    def RequestPinCode(self, device):
        print(f'RequestPinCode {device}')
        return '0000'


class Device:
    def __init__(self, device_path):
        dev_obj = bus.get_object(BUS_NAME, device_path)
        self.methods = dbus.Interface(dev_obj, DEVICE_IFACE)
        self.props = dbus.Interface(dev_obj, dbus.PROPERTIES_IFACE)
        self._port = 1
        self._client_sock = socket.socket(socket.AF_BLUETOOTH,
                                          socket.SOCK_STREAM,
                                          socket.BTPROTO_RFCOMM)

    def connect(self):
        # self.methods.Connect()
        self._client_sock.bind((my_adapter_address, self._port))
        self._client_sock.connect((self.address, self._port))

    def disconnect(self):
        self.methods.Disconnect()

    def pair(self):
        self.methods.Pair(reply_handler=self._pair_reply,
                          error_handler=self._pair_error)

    def _pair_reply(self):
        print(f'Device trusted={self.trusted}, connected={self.connected}')
        self.trusted = True
        print(f'Device trusted={self.trusted}, connected={self.connected}')
        while self.connected:
            sleep(0.5)
        self.connect()
        print('Successfully paired and connected')

    def _pair_error(self, error):
        err_name = error.get_dbus_name()
        print(f'Creating device failed: {err_name}')

    @property
    def trusted(self):
        return bool(self.props.Get(DEVICE_IFACE, 'Trusted'))

    @trusted.setter
    def trusted(self, value):
        self.props.Set(DEVICE_IFACE, 'Trusted', bool(value))

    @property
    def paired(self):
        return bool(self.props.Get(DEVICE_IFACE, 'Paired'))

    @property
    def connected(self):
        return bool(self.props.Get(DEVICE_IFACE, 'Connected'))

    @property
    def address(self):
        return str(self.props.Get(DEVICE_IFACE, 'Address'))


if __name__ == '__main__':
    agent = Agent(bus, AGENT_PATH)

    agnt_mngr = dbus.Interface(bus.get_object(BUS_NAME, AGNT_MNGR_PATH),
                               AGNT_MNGR_IFACE)
    agnt_mngr.RegisterAgent(AGENT_PATH, CAPABILITY)

    device = Device(my_device_path)
    if device.paired:
        device.connect()
    else:
        device.pair()


    mainloop = GLib.MainLoop()
    try:
        mainloop.run()
    except KeyboardInterrupt:
        agnt_mngr.UnregisterAgent(AGENT_PATH)
        mainloop.quit()

