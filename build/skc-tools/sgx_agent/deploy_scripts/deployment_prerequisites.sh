#!/bin/bash

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

install_pre_requisites()
{
	if [[ "$OS" == "rhel" && "$VER" == "8.1" || "$VER" == "8.2" ]]; then
		dnf install -qy https://dl.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/e/epel-release-8-11.el8.noarch.rpm || exit 1
		dnf install -qy yum-utils kernel-devel dkms tar make jq || exit 1
	elif [[ "$OS" == "ubuntu" && "$VER" == "18.04" ]]; then
		apt install -y dkms tar make jq curl || exit 1
		sed -i "/msr/d" /etc/modules
		sed -i "$ a msr" /etc/modules
		modprobe msr || exit 1
	else
		echo "${red} Unsupported OS. Please use RHEL 8.1/8.2 or Ubuntu 18.04 ${reset}"
		exit 1
	fi
}

install_pre_requisites
