#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import socket
import sys
import threading
import time
import libvirt
import multiprocessing
import logging
logging.basicConfig(encoding='utf-8', level=logging.INFO, format='%(asctime)s %(levelname)s: %(message)s')
logging.getLogger().setLevel(level=os.getenv('LOG', 'INFO').upper())
logger = logging.getLogger(__name__)

SOCKET_QUEUE_BACKLOG = 0
CTRL_Q = '\x11'
BASE_DIRECTORY = '/tmp'

class SocketServer(multiprocessing.Process):
    def __init__(self, uuid, url):
        multiprocessing.Process.__init__(self)

        self._uuid = uuid
        self._url = url
        self._server_addr = os.path.join(BASE_DIRECTORY, uuid)
        if os.path.exists(self._server_addr):
            raise RuntimeError('There is an existing connection to %s' % uuid)
        self._socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self._socket.bind(self._server_addr)
        self._socket.listen(SOCKET_QUEUE_BACKLOG)
        logger.info('[%s] socket server to guest %s created', self.name, uuid)

    def run(self):
        self.listen()

    def _is_vm_listening_serial(self, console):
        is_listening = []
        def _test_output(stream, event, opaque):
            is_listening.append(1)
        def _event_loop():
            while not is_listening:
                libvirt.virEventRunDefaultImpl()

        console.eventAddCallback(libvirt.VIR_STREAM_EVENT_READABLE, _test_output, None)
        libvirt_loop = threading.Thread(target=_event_loop)
        libvirt_loop.start()

        console.send(b'\n')
        libvirt_loop.join(1)

        if not libvirt_loop.is_alive():
            console.eventRemoveCallback()
            return True

        console.eventRemoveCallback()
        return False

    def _send_to_client(self, stream, event, opaque):
        try:
            data = stream.recv(1024)
        except Exception as e:
            logger.info('[%s] Error when reading from console: %s', self.name, str(e))
            return
        # return if no data received or client socket(opaque) is not valid
        if not data or not opaque:
            return
        opaque.send(data)

    def libvirt_event_loop(self, guest, client):
        while guest.is_running():
            libvirt.virEventRunDefaultImpl()
        # shutdown the client socket to unblock the recv and stop the
        # server as soon as the guest shuts down
        client.shutdown(socket.SHUT_RD)

    def listen(self):
        libvirt.virEventRegisterDefaultImpl()
        try:
            guest = LibvirtGuest(self._uuid, self._url, self.name)
        except Exception as e:
            logger.error(f'{self.name} Cannot open the guest {self._uuid} due to {str(e)}')
            self._socket.close()
            sys.exit(1)

        except (KeyboardInterrupt, SystemExit):
            self._socket.close()
            sys.exit(1)

        console = None
        try:
            console = guest.get_console()
            if console is None:
                logger.error('[%s] Cannot get the console to %s', self.name, self._uuid)
                return
            if not self._is_vm_listening_serial(console):
                sys.exit(1)
            self._listen(guest, console)
        # clear resources aquired when the process is killed
        except (KeyboardInterrupt, SystemExit):
            pass
        finally:
            logger.info('[%s] Shutting down the socket server to %s console', self.name, self._uuid,)
            self._socket.close()
            if os.path.exists(self._server_addr):
                os.unlink(self._server_addr)
            try:
                console.eventRemoveCallback()
            except Exception as e:
                logger.info('[%s] Callback is probably removed: %s', self.name, str(e))
            guest.close()

    def _listen(self, guest, console):
        client, client_addr = self._socket.accept()
        session_timeout = 20
        client.settimeout(int(session_timeout) * 60)
        logger.info('[%s] Client connected to %s', self.name, self._uuid)
        # register the callback to receive any data from the console
        console.eventAddCallback(libvirt.VIR_STREAM_EVENT_READABLE, self._send_to_client, client)

        # start the libvirt event loop in a python thread
        libvirt_loop = threading.Thread(target=self.libvirt_event_loop, args=(guest, client))
        libvirt_loop.start()
        while True:
            data = ''
            try:
                data = client.recv(1024)
            except Exception as e:
                logger.info('[%s] Client disconnected from %s: %s', self.name, self._uuid, str(e),)
                break
            if not data or data == CTRL_Q:
                break
            # if the console can no longer be accessed, close everything
            # and quits
            try:
                console.send(data)
            except Exception:
                logger.info('[%s] Console of %s is not accessible', self.name, self._uuid)
                break
        # clear used resources when the connection is closed and, if possible,
        # tell the client the connection was lost.
        try:
            client.send(b'\\r\\n\\r\\nClient disconnected\\r\\n')
        except Exception:
            pass


class LibvirtGuest(object):
    def __init__(self, uuid, uri, process_name):
        self._proc_name = process_name
        try:
            conn = libvirt.open(uri)
            self._guest = conn.lookupByUUIDString(uuid)
        except Exception as e:
            logger.error('[%s] Cannot open guest %s: %s', self._proc_name, uuid, str(e))
            raise
        self.conn = conn
        self._name = uuid
        self._stream = None

    def is_running(self):
        return (
            self._guest.state(0)[0] == libvirt.VIR_DOMAIN_RUNNING or
            self._guest.state(0)[0] == libvirt.VIR_DOMAIN_PAUSED
        )

    def get_console(self):
        # guest must be in a running state to get its console
        counter = 10
        while not self.is_running():
            logger.info('[%s] Guest %s is not running, waiting for it', self._proc_name, self._name,)
            counter -= 1
            if counter <= 0:
                return None
            time.sleep(1)

        # attach a stream in the guest console so we can read from/write to it
        if self._stream is None:
            logger.info('[%s] Opening the console for guest %s', self._proc_name, self._name)
            self._stream = self.conn.newStream(libvirt.VIR_STREAM_NONBLOCK)
            self._guest.openConsole(None, self._stream, libvirt.VIR_DOMAIN_CONSOLE_FORCE | libvirt.VIR_DOMAIN_CONSOLE_SAFE,)
        return self._stream

    def close(self):
        self.conn.close()

def main(url, uuid):
    server = None
    try:
        server = SocketServer(uuid, url)
    except Exception as e:
        logger.error('Cannot create the socket server: %s', str(e))
        raise
    server.start()
    return server

if __name__ == '__main__':
    argc = len(sys.argv)
    if argc != 3:
        print(f'usage: {sys.argv[0]} <url> <uuid>')
        sys.exit(1)
    print(f'nc -U /tmp/{sys.argv[2]}')
    main(sys.argv[1], sys.argv[2])
