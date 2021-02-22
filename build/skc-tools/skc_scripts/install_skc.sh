#!/bin/bash
# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')
OS_FLAVOUR="$OS""$VER"

if [[ "$OS" == "rhel" && "$VER" == "8.1" || "$VER" == "8.2" ]]; then
        dnf install -y jq
elif [[ "$OS" == "ubuntu" && "$VER" == "18.04" ]]; then
        apt install -y jq curl
else
        echo "Unsupported OS. Please use RHEL 8.1/8.2 or Ubuntu 18.04"
        exit 1
fi

source install_basic.sh
if [ $? -ne 0 ]
then
        echo "skc basic component installation failed"
        exit
fi

source install_orchestrator.sh
if [ $? -ne 0 ]
then
        echo "SHVS/IHUB installation failed"
        exit
fi
