#!/bin/bash
SKCLIB_DIR=skc_library
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

create_skc_library_tar()
{
	\cp -pf ../deploy_scripts/*.sh $SKCLIB_DIR
	\cp -pf ../deploy_scripts/skc_library.conf $SKCLIB_DIR
	\cp -pf ../deploy_scripts/create_roles.conf $SKCLIB_DIR
	\cp -pf ../deploy_scripts/README.install $SKCLIB_DIR
	\cp -pf ../deploy_scripts/openssl.patch $SKCLIB_DIR
	\cp -pf ../deploy_scripts/nginx.patch $SKCLIB_DIR
	tar -cf $TAR_NAME.tar -C $SKCLIB_DIR . --remove-files || exit 1
	sha256sum $TAR_NAME.tar > $TAR_NAME.sha2
	echo "skc_library.tar file and skc_library.sha2 checksum file created"
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
create_skc_library_tar
