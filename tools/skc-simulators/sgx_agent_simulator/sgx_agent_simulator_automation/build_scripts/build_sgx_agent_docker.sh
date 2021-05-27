#!/bin/bash
SGX_AGENT_DIR=sgx_agent
SGX_AGENT_BIN_DIR=$SGX_AGENT_DIR/bin
TAR_NAME=$(basename $SGX_AGENT_DIR)

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')

create_sgx_agent_tar()
{
	\cp -pf ../deploy_scripts/deployment_prerequisites.sh $SGX_AGENT_DIR
	\cp -pf ../deploy_scripts/README.install $SGX_AGENT_DIR
	tar -cf $TAR_NAME.tar -C $SGX_AGENT_DIR . --remove-files
	sha256sum $TAR_NAME.tar > $TAR_NAME.sha2
	echo "sgx_agent.tar file and sgx_agent.sha2 checksum file created"
}

build_sgx_agent_docker()
{
        pushd $PWD
        \cp -prf $SGX_AGENT_BIN_DIR ../../../../../sgx_agent/dist/image/
        if [ "$OS" == "rhel" ]
        then
                tar -xf ../../../../../sgx_agent/dist/image/bin/sgx_rpm_local_repo.tgz -C ../../../../../sgx_agent/dist/image/bin/
        fi
        cd ../../../../../sgx_agent
        make oci-archive || exit 1
        rm -rf dist/image/bin
        popd
}

if [ "$OS" == "rhel" ]
then
 rm -f /etc/yum.repos.d/*sgx_rpm_local_repo.repo
fi

source build_prerequisites.sh
if [ $? -ne 0 ]
then
	echo "failed to resolve package dependencies"
	exit
fi

source download_dcap_driver.sh  
if [ $? -ne 0 ]
then
        echo "sgx dcap driver download failed"
        exit
fi

source install_sgxsdk.sh
if [ $? -ne 0 ]
then
        echo "sgxsdk install failed"
        exit
fi

source download_sgx_psw_qgl.sh
if [ $? -ne 0 ]
then
        echo "sgx psw, qgl rpms download failed"
        exit
fi

source download_mpa_uefi_rpm.sh  
if [ $? -ne 0 ]
then
        echo "mpa uefi rpm download failed"
        exit
fi

source build_pckretrieval_tool.sh
if [ $? -ne 0 ]
then
        echo "pckretrieval tool build failed"
        exit
fi

build_sgx_agent_docker
if [ $? -ne 0 ]
then
        echo "sgx agent docker build failed"
        exit
fi

create_sgx_agent_tar
if [ $? -ne 0 ]
then
        echo "failed to create sgx agent tar"
        exit
fi

