#!/bin/bash

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')
OS_FLAVOUR="$OS""$VER"

install_pre_requisites()
{
	if [[ "$OS" == "rhel" && "$VER" == "8.1" || "$VER" == "8.2" ]]; then
		dnf install -y https://dl.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/e/epel-release-8-10.el8.noarch.rpm
		dnf install -y yum-utils kernel-devel dkms tar make jq || exit 1
	elif [[ "$OS" == "ubuntu" && "$VER" == "18.04" ]]; then
		apt install -y dkms tar make jq curl
		modprobe msr
	else
		echo "Unsupported OS. Please use RHEL 8.1/8.2 or Ubuntu 18.04"
		exit 1
	fi
}

install_pre_requisites
