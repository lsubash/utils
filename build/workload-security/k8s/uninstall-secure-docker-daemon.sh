#!/bin/bash

DOCKER_DAEMON_PATH=/etc/docker/daemon.json
SECURE_DOCKER_DAMEON=/opt/secure-docker-daemon

systemctl stop docker
systemctl stop secure-docker-plugin.service
systemctl disable secure-docker-plugin.service 2>/dev/null

which /usr/bin/dockerd-ce 2>/dev/null
if [ $? -ne 0 ]; then
  yes | cp -fr $SECURE_DOCKER_DAMEON/backup/dockerd /usr/bin/dockerd
  yes | cp -fr $SECURE_DOCKER_DAMEON/backup/docker /usr/bin/docker
else
  yes | cp -rf $SECURE_DOCKER_DAMEON/backup/dockerd-ce /usr/bin/dockerd-ce
fi

 # backup config files
if [ -f $SECURE_DOCKER_DAMEON/backup/daemon.json ]; then
  yes | cp -f $SECURE_DOCKER_DAMEON/backup/daemon.json $DOCKER_DAEMON_PATH
else
  rm -f $DOCKER_DAEMON_PATH
fi

echo "Starting docker engine"
systemctl daemon-reload
systemctl start docker
if [ $? -eq 0 ]; then
  rm -rf $SECURE_DOCKER_DAMEON
fi