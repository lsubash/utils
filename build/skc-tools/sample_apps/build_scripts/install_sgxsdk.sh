#!/bin/bash
SGX_INSTALL_DIR=/opt/intel
SGX_VERSION=2.13

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')
OS_FLAVOUR="$OS""$VER"

SGX_URL="https://download.01.org/intel-sgx/sgx-linux/${SGX_VERSION}/distro/$OS_FLAVOUR-server"
SGX_SDK_VERSION=2.13.100.4

install_sgxsdk()
{
	wget -q $SGX_URL/sgx_linux_x64_sdk_$SGX_SDK_VERSION.bin || exit 1
	chmod +x sgx_linux_x64_sdk_$SGX_SDK_VERSION.bin
	./sgx_linux_x64_sdk_$SGX_SDK_VERSION.bin -prefix=$SGX_INSTALL_DIR || exit 1
	source $SGX_INSTALL_DIR/sgxsdk/environment
	if [ $? -ne 0 ]; then
		echo "failed while setting sgx environment"
		exit 1
	fi
	rm -rf sgx_linux_x64_sdk_$SGX_SDK_VERSION.bin
}

install_sgxsdk
