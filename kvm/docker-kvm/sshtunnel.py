# -*- coding: utf-8 -*-
import flask_app, os, json
from config import config
logger=flask_app.logger

import functools
import queue
import signal
import socket
import threading

class _Tunnel(object):
    def __init__(self):
        self._pid = None
        self._closed = False
        self._errfd = None

    def close(self):
        if self._closed:
            return
        self._closed = True
        logger.info("Close tunnel PID=%s ERRFD=%s", self._pid, self._errfd and self._errfd.fileno() or None)
        self._errfd = None
        if self._pid:
            os.kill(self._pid, signal.SIGKILL)
            os.waitpid(self._pid, 0)
        self._pid = None

    def get_err_output(self):
        errout = ""
        while True:
            try:
                new = self._errfd.recv(1024)
            except Exception:
                break
            if not new:
                break
            errout += new.decode()
        return errout

    def open(self, argv, sshfd):
        if self._closed:
            return
        errfds = socket.socketpair()
        pid = os.fork()
        if pid == 0:
            errfds[0].close()
            os.dup2(sshfd.fileno(), 0)
            os.dup2(sshfd.fileno(), 1)
            os.dup2(errfds[1].fileno(), 2)
            os.execlp(*argv)
            os._exit(1)
        sshfd.close()
        errfds[1].close()
        self._errfd = errfds[0]
        self._errfd.setblocking(0)
        logger.info("Opened tunnel PID=%d ERRFD=%d", pid, self._errfd.fileno())
        self._pid = pid

def _make_ssh_command(connhost, connuser, connport, gaddr, gport, gsocket):
    argv = ["ssh", "ssh"]
    if connport:
        argv += ["-p", str(connport)]
    if connuser:
        argv += ["-l", connuser]
    argv += [connhost]
    # Build 'nc' command run on the remote host
    if gsocket:
        nc_params = "-U %s" % gsocket
    else:
        nc_params = "%s %s" % (gaddr, gport)
    nc_cmd = (
        """nc -q 2>&1 | grep "requires an argument" >/dev/null;"""
        """if [ $? -eq 0 ] ; then"""
        """   CMD="nc -q 0 %(nc_params)s";"""
        """else"""
        """   CMD="nc %(nc_params)s";"""
        """fi;"""
        """eval "$CMD";""" % {"nc_params": nc_params}
    )
    argv.append("sh -c")
    argv.append("'%s'" % nc_cmd)
    argv_str = functools.reduce(lambda x, y: x + " " + y, argv[1:])
    logger.info("Pre-generated ssh command for info: %s", argv_str)
    return argv

class SSHTunnels(object):
    def __init__(self, connhost, connuser, connport, gaddr, gport, gsocket):
        self._tunnels = []
        self._sshcommand = _make_ssh_command(
            connhost, connuser, connport, gaddr, gport, gsocket
        )
        self._locked = False

    def open_new(self):
        t = _Tunnel()
        self._tunnels.append(t)
        # socket FDs are closed when the object is garbage collected. This
        # can close an FD behind spice/vnc's back which causes crashes.
        #
        # Dup a bare FD for the viewer side of things, but keep the high
        # level socket object for the SSH side, since it simplifies things
        # in that area.
        viewerfd, sshfd = socket.socketpair()
        _tunnel_scheduler.schedule(self._lock, t.open, self._sshcommand, sshfd)

        retfd = os.dup(viewerfd.fileno())
        logger.info("Generated tunnel fd=%s for viewer", retfd)
        return retfd

    def close_all(self):
        for l in self._tunnels:
            l.close()
        self._tunnels = []
        self.unlock()

    def get_err_output(self):
        errstrings = []
        for l in self._tunnels:
            e = l.get_err_output().strip()
            if e and e not in errstrings:
                errstrings.append(e)
        return "\n".join(errstrings)


############################################################
import shutil
SOCAT_COMMAND = shutil.which('socat')

PARSER = argparse.ArgumentParser(description="Forward unix sockets over SSH")
PARSER.add_argument("--local_path", help="override the local path. If not given, mirrors the remote_path")
PARSER.add_argument("--local_user", help="try to set the user the local socket is owned by")
PARSER.add_argument("--local_group", help="try to set the group the local socket is owned by")
PARSER.add_argument("--local_mode", help="try to set the file mode of the local socket")
PARSER.add_argument("ssh_command", help="command to connect to the remote host. Example: ssh myuser@myhost")
PARSER.add_argument("remote_path", help="path to the remote socket to forward")

def main():
    args = PARSER.parse_args()
    logging.debug(args)

    socat_local_opts = []
    for opt_name in ('user', 'group', 'mode'):
        opt_val = getattr(args, 'local_%s' % opt_name)
        if opt_val:
            socat_local_opts.append('%s=%s' % (opt_name, opt_val))

    socat_local_opts_suffix = ''.join((
        ',%s' % opt_string for opt_string in socat_local_opts
    ))

    real_socat_command = (SOCAT_COMMAND,
                         'UNIX-LISTEN:{local_path},reuseaddr,fork%s' % socat_local_opts_suffix,
                         'EXEC:{ssh_command} socat STDIO UNIX-CONNECT\\:{remote_path}',
                         )
    remote_path = args.remote_path
    local_path = args.local_path or remote_path
    real_socat_command = [
        s.format(
            local_path=local_path,
            remote_path=remote_path,
            ssh_command=args.ssh_command,
        )
        for s in real_socat_command]
    logging.debug("Real socat command: %s", real_socat_command)

    logging.info("Spawning the socat process")
    os.execvp(real_socat_command[0], real_socat_command)


# # no use fork,reuseaddr!
local = 'UNIX-LISTEN:/tmp/unix-sock'
remote = 'TCP:localhost:9999'
ssh_cmd = f'ssh -p60022 root@192.168.168.1 socat STDIO {remote}'
socat_cmd = ('socat', f'{local},unlink-early', f'EXEC:"{ssh_cmd}"',)
pid = os.fork()
if pid == 0:
    os.execvp(socat_cmd[0], socat_cmd)
logger.info("Opened tunnel PID=%d, %s", pid, socat_cmd)

# import signal
# os.kill(pid, signal.SIGKILL)
os.waitpid(pid, 0)
