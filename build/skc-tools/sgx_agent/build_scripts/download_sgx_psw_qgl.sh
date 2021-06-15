#!/bin/bash
SGX_AGENT_DIR=$PWD/sgx_agent
SGX_AGENT_BIN_DIR=$SGX_AGENT_DIR/bin
SGX_VERSION=2.13.3

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')
OS_FLAVOUR="$OS""$VER"

SGX_URL="https://download.01.org/intel-sgx/sgx-linux/${SGX_VERSION}/distro/$OS_FLAVOUR-server"

download_psw_qpl_qgl()
{
	if [ "$OS" == "rhel" ]; then
		wget -q $SGX_URL/sgx_rpm_local_repo.tgz -P $SGX_AGENT_BIN_DIR || exit 1
	fi
}

download_psw_qpl_qgl
