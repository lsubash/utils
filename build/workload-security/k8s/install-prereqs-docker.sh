#!/bin/bash

SECURE_DOCKER_DAMEON=/opt/secure-docker-daemon
mkdir -p $SECURE_DOCKER_DAMEON
DOCKER_DAEMON_PATH=/etc/docker/daemon.json
# Check OS
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"

install_secure_docker_plugin(){

source secure-docker-plugin.env

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
cp -r artifact/* /lib/systemd/system/

systemctl daemon-reload
systemctl enable secure-docker-plugin.service 2>/dev/null
systemctl start secure-docker-plugin.service
}

is_docker_installed(){
  which docker 2>/dev/null
  if [ $? -ne 0 ]; then
    echo_failure "Container Security requires Docker 19.03 to be installed on this system, but docker is not installed"
    exit 1
  fi
}

configure_daemon_json_file(){
  sed -i -r '/^\s*$/d' $DOCKER_DAEMON_PATH
  sed -i '1d;$d' $DOCKER_DAEMON_PATH
  sed -i -r '/^\s*$/d' $DOCKER_DAEMON_PATH
  no_lines=$(wc -l < $DOCKER_DAEMON_PATH)
  if [ "$no_lines" == 1 ]; then
    echo -n "," >> $DOCKER_DAEMON_PATH
  fi
  authz_plugins=$(grep authorization-plugins $DOCKER_DAEMON_PATH  |   cut -d ":" -f 2 | cut -d "[" -f 2 | cut -d "]" -f 1)
  sed -i "s/\"storage-driver\":.*//g" $DOCKER_DAEMON_PATH
  sed -i "s/\"authorization-plugins\":.*//g" $DOCKER_DAEMON_PATH
  if [ ! -z $authz_plugins ]; then
     authz_plugins="[$authz_plugins,\"secure-docker-plugin\"],"
  else
     authz_plugins="\"authorization-plugins\": [\"secure-docker-plugin\"],"
  fi
  storage_driver="\"storage-driver\": \"secureoverlay2\""
  echo $authz_plugins >> $DOCKER_DAEMON_PATH
  echo $storage_driver >> $DOCKER_DAEMON_PATH


  sed -i "1s/^/{ /" $DOCKER_DAEMON_PATH
  echo "}" >> $DOCKER_DAEMON_PATH
  cat $DOCKER_DAEMON_PATH
}

is_docker_installed

which cryptsetup 2>/dev/null
if [ $? -ne 0 ]; then
  if [ "$OS" == "rhel" ]; then
     yum install -y cryptsetup
  fi
  if [ "$OS" == "ubuntu" ]; then
     apt install -y cryptsetup
  fi
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
if [ -f $DOCKER_DAEMON_PATH ]; then
  cp $DOCKER_DAEMON_PATH $SECURE_DOCKER_DAMEON/backup/
  configure_daemon_json_file
else
  cat > $DOCKER_DAEMON_PATH <<EOF
{
 "authorization-plugins": ["secure-docker-plugin"],
 "storage-driver": "secureoverlay2"
}
EOF
fi
cp /lib/systemd/system/docker.service $SECURE_DOCKER_DAMEON/backup/

install_secure_docker_plugin

echo "Starting secure docker engine"
systemctl daemon-reload
systemctl start docker
