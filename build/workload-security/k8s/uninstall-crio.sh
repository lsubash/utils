#!/bin/bash

CRIO_BAKCUP_DIR=/opt/crio/backup/

CRIO_PATH=$(which crio 2>/dev/null)
if [ $? -ne 0 ]; then
  echo_failure "Container Security requires crio v1.17 to be installed on this system, but crio is not installed"
  exit 1
fi

systemctl stop crio
yes | cp -f $CRIO_BAKCUP_DIR/crio $CRIO_PATH


sed -i "s#ExecStart=$CRIO_PATH --decryption-secl-parameters secl:enabled #ExecStart=$CRIO_PATH #g" /usr/lib/systemd/system/crio.service
systemctl daemon-reload
systemctl start crio
if [ $? -eq 0 ]; then
  rm -rf $CRIO_BAKCUP_DIR
fi