#!/bin/bash

CRIO_BAKCUP_DIR=/opt/crio/backup/
CRIO_PATH=$(which crio 2>/dev/null)
if [ $? -ne 0 ]; then
  echo_failure "Container Security requires crio v1.17 to be installed on this system, but crio is not installed"
  exit 1
fi

systemctl stop crio

# Take backup of existing docker CLI and daemon binaries and configs
mkdir -p $CRIO_BAKCUP_DIR
cp $CRIO_PATH $CRIO_BAKCUP_DIR

cp -f crio /usr/bin/
sed -i "s#ExecStart=$CRIO_PATH #ExecStart=$CRIO_PATH --decryption-secl-parameters secl:enabled #g" /usr/lib/systemd/system/crio.service
systemctl daemon-reload
systemctl start crio
