#!/bin/bash
DCAP_VERSION=1.10
SGX_DCAP_TAG=DCAP_1.10
OS_FLAVOUR="rhel8.2-server"
MULTIPACKAGE_AGENT_RPM="https://download.01.org/intel-sgx/sgx-dcap/$DCAP_VERSION/linux/tools/SGXMultiPackageAgent/$OS_FLAVOUR"
SGX_DCAP_REPO="https://github.com/intel/SGXDataCenterAttestationPrimitives.git"
GIT_CLONE_PATH=/tmp/dataCenterAttestationPrimitives
MP_RPM_VER=1.10.100.4-1

install_sgx_components()
{
	rm -rf $GIT_CLONE_PATH

	echo "Please provide patch file path"
	read path
	if [ ! -f $path/remove_pccs_connect.diff ]; then
		echo "file not found on the given path"
		exit 1
	fi

	# install uefi rpm to extract manifest file
	rpm -ivh $MULTIPACKAGE_AGENT_RPM/libsgx-ra-uefi-$MP_RPM_VER.el8.x86_64.rpm

	# build and  install PCKidretrieval tool
	git clone $SGX_DCAP_REPO $GIT_CLONE_PATH/
	cd $GIT_CLONE_PATH/
	git checkout $SGX_DCAP_TAG
	cp $path/remove_pccs_connect.diff $GIT_CLONE_PATH/
	cd $GIT_CLONE_PATH/tools/PCKRetrievalTool
	git apply $path/remove_pccs_connect.diff
	make
	cp -u libdcap_quoteprov.so.1 pck_retrieve_tool_enclave.signed.so PCKIDRetrievalTool /usr/local/bin
}

install_sgx_components
