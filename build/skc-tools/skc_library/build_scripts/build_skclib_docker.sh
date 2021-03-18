#!/bin/bash
SKCLIB_DIR=skc_library
SKCLIB_BIN_DIR=$SKCLIB_DIR/bin
TAR_NAME=$(basename $SKCLIB_DIR)

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')

install_prerequisites()
{
	source build_prerequisites.sh	
	if [ $? -ne 0 ]; then
		"Pre-build step failed"
		exit 1
	fi
}

download_dcap_driver()
{
	source download_dcap_driver.sh
	if [ $? -ne 0 ]; then
		echo "sgx dcap driver download failed"
		exit 1
	fi
}

install_sgxsdk()
{
	source install_sgxsdk.sh
	if [ $? -ne 0 ]; then
		echo "sgx sdk installation failed"
		exit 1
	fi
}

install_sgxrpm()
{
	source install_sgxrpms.sh
	if [ $? -ne 0 ]; then
		echo "sgx psw/qgl rpm installation failed"
		exit 1
	fi
}
	
install_ctk()
{
	source install_ctk.sh
	if [ $? -ne 0 ]; then
		echo "cryptoapitoolkit installation failed"
		exit 1
	fi
}

build_skc_library()
{
	source build_skclib.sh
	if [ $? -ne 0 ]; then
		echo "skc_library build failed"
		exit 1
	fi
}

build_skc_library_docker()
{
        pushd $PWD
        \cp -prf $SKCLIB_DIR/cryptoapitoolkit ../../../../../skc_library/dist/image/
        \cp -prf $SKCLIB_DIR/sgxssl ../../../../../skc_library/dist/image/
        \cp -prf ../deploy_scripts/skc_library.conf ../../../../../skc_library/dist/image/
        \cp -prf $SKCLIB_BIN_DIR ../../../../../skc_library/dist/image/
        \cp -prf ../deploy_scripts/credential_agent.sh ../../../../../skc_library/dist/image/
	if [ "$OS" == "rhel" ]
	then
		tar -xf ../../../../../skc_library/dist/image/bin/sgx_rpm_local_repo.tgz -C ../../../../../skc_library/dist/image/bin/ || exit 1
	fi
        cd ../../../../../skc_library
        mkdir -p out
        make oci-archive || exit 1
        rm -rf dist/image/cryptoapitoolkit dist/image/sgxssl dist/image/bin dist/image/skc_library.conf dist/image/credential_agent.sh
        popd
}

rm -rf $SKCLIB_DIR

if [ "$OS" == "rhel" ]
then
  rm -f /etc/yum.repos.d/*sgx_rpm_local_repo.repo
fi

install_prerequisites
download_dcap_driver
install_sgxsdk
install_sgxrpm
install_ctk
build_skc_library
build_skc_library_docker
if [ $? -ne 0 ]; then
	echo "skc_library docker build failed"
	exit 1
fi

