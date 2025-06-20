# Tunneling Ethernet Over SSH With Socat and Tap Devices

There are circumstances where one wants to attach the local machine
to the same layer 2 ethernet segment, which a remote machine is connected to,
with the only available transport being SSH.

While this solution has quite some shortcomings and should not be used
to replace a real VPN, it can be beneficial e.g. for debugging network
issues remotely.

Therefore, without further ado: Ethernet over SSH

## Server

Socat needs to be installed. SSH to the server using `-L 1234:127.0.0.1:1234` or
call that command inside of the established session. (Use `~C` to open a command prompt.)

```console
socat TUN,tun-type=tap,iff-up TCP-LISTEN:1234,bind=127.0.0.1,reuseaddr
```

The resulting tap device should be bridged to the network which you want to connect to.

## Client

Socat needs to be installed here as well. Connect to the previously started socat using:

```console
socat TUN,tun-type=tap,iff-up TCP:127.0.0.1:1234
```

That's it. Your local `tap0` (as it is most likely called) is bridged all the way to the remote ethernet.
