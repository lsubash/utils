#!/bin/bash

SECURE_DOCKER_DAMEON=/opt/secure-docker-daemon

install_secure_docker_plugin(){

mkdir /etc/systemd/system/secure-docker-plugin.service.d 2>1 /dev/null

cat > /etc/systemd/system/secure-docker-plugin.service.d/securedockerplugin.conf <<EOF
[Service]
Environment="INSECURE_SKIP_VERIFY=${INSECURE_SKIP_VERIFY:-true}"
Environment="NO_PROXY=${NO_PROXY}"
Environment="REGISTRY_SCHEME_TYPE=${REGISTRY_SCHEME_TYPE:-https}"
Environment="REGISTRY_USERNAME=${REGISTRY_USERNAME}"
Environment="REGISTRY_PASSWORD=${REGISTRY_PASSWORD}"
Environment="HTTPS_PROXY=${HTTPS_PROXY}"
EOF

cp secure-docker-plugin /usr/bin/
cp artifact/* /lib/systemd/system/

systemctl daemon-reload
systemctl enable secure-docker-plugin.service 2>/dev/null
systemctl start secure-docker-plugin.service
}

is_docker_installed

which cryptsetup 2>/dev/null
if [ $? -ne 0 ]; then
  yum install -y cryptsetup
  CRYPTSETUP_RESULT=$?
  if [ $CRYPTSETUP_RESULT -ne 0 ]; then
    echo_failure "Error: Secure Docker Daemon requires cryptsetup - Install failed. Exiting."
    exit $CRYPTSETUP_RESULT
  fi
fi
echo "Installing secure docker daemon"
systemctl stop docker

# Take backup of existing docker CLI and daemon binaries and configs
mkdir -p $SECURE_DOCKER_DAMEON/backup/
cp /usr/bin/docker $SECURE_DOCKER_DAMEON/backup/
chown -R root:root docker-daemon/

cp -f docker /usr/bin/
which /usr/bin/dockerd-ce 2>/dev/null
if [ $? -ne 0 ]; then
  cp /usr/bin/dockerd $SECURE_DOCKER_DAMEON/backup/
  cp -f dockerd-ce /usr/bin/dockerd
else
  cp /usr/bin/dockerd-ce $SECURE_DOCKER_DAMEON/backup/
  cp -f dockerd-ce /usr/bin/dockerd-ce
fi

  # backup config files
if [ -f "/etc/docker/daemon.json" ]; then
  cp /etc/docker/daemon.json $SECURE_DOCKER_DAMEON/backup/
fi
cp /lib/systemd/system/docker.service $SECURE_DOCKER_DAMEON/backup/

install_secure_docker_plugin

echo "Starting secure docker engine"
mkdir -p /etc/docker
cp daemon.json /etc/docker/
systemctl daemon-reload
systemctl start docker