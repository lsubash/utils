#!/bin/bash
SGX_AGENT_DIR=$PWD/sgx_agent
DCAP_VERSION=1.10.3
SGX_AGENT_BIN_DIR=$SGX_AGENT_DIR/bin
MP_RPM_VER=1.10.103.1-1

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')
OS_FLAVOUR="$OS""$VER"

MPA_URL="https://download.01.org/intel-sgx/sgx-dcap/$DCAP_VERSION/linux/tools/SGXMultiPackageAgent/$OS_FLAVOUR-server"

fetch_mpa_uefi_rpm() {
	if [ "$OS" == "rhel" ]; then
		wget -q $MPA_URL/sgx_rpm_local_repo.tgz -O - | tar -xz || exit 1
		\cp sgx_rpm_local_repo/libsgx-ra-uefi-$MP_RPM_VER.el8.x86_64.rpm $SGX_AGENT_BIN_DIR
		rm -rf sgx_rpm_local_repo sgx_rpm_local_repo.tgz
	elif [ "$OS" == "ubuntu" ]; then
		wget -q https://download.01.org/intel-sgx/sgx-dcap/$DCAP_VERSION/linux/tools/SGXMultiPackageAgent/$OS_FLAVOUR-server/debian_pkgs/libs/libsgx-ra-uefi/libsgx-ra-uefi_1.9.100.3-bionic1_amd64.deb -P $SGX_AGENT_BIN_DIR || exit 1
	fi
}

fetch_mpa_uefi_rpm
