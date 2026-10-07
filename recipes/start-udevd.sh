#!/bin/sh
/usr/sbin/udevd --daemon
/usr/bin/udevadm trigger --type=devices --action=add
/usr/bin/udevadm trigger --type=subsystems --action=add
/usr/bin/udevadm settle --timeout=10
