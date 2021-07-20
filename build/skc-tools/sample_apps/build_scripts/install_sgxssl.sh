#!/bin/bash
SAMPLEAPPS_DIR=sample_apps
SGX_INSTALL_DIR=/opt/intel
SGXSSL_PREFIX=$SGX_INSTALL_DIR/sgxssl
LINUX_SGX_REPO="https://github.com/intel/linux-sgx.git"
SGX_SSL_REPO="https://github.com/intel/intel-sgx-ssl.git"
GIT_CLONE_PATH=/tmp/sgx
GIT_CLONE_LINUX_SGXSSL=$GIT_CLONE_PATH/linux-sgx
GIT_CLONE_SGXSSL=$GIT_CLONE_PATH/intel-sgx-ssl

# Check OS and VERSION
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"
VER=$(cat /etc/os-release | grep ^VERSION_ID | tr -d 'VERSION_ID="')

install_sgxssl()
{
        pushd $PWD

        rm -rf $GIT_CLONE_PATH
        mkdir -p $GIT_CLONE_PATH

        git clone $LINUX_SGX_REPO $GIT_CLONE_LINUX_SGXSSL ||exit 1
        git clone $SGX_SSL_REPO $GIT_CLONE_SGXSSL ||exit 1

        cd $GIT_CLONE_LINUX_SGXSSL
        make preparation
        if [[ "$OS" == "rhel" &&  "$VER" == "8.2" ]]; then
                cp external/toolset/rhel8.2/{as,ld,ld.gold,objdump} /usr/local/bin || exit 1
        elif [[ "$OS" == "ubuntu" && "$VER" == "18.04" ]]; then
                sudo cp external/toolset/ubuntu18.04/{as,ld,ld.gold,objdump} /usr/local/bin
        else
                echo "Unsupported OS. Please use RHEL 8.2 or Ubuntu 18.04"
                exit 1
        fi

        cd $GIT_CLONE_SGXSSL/openssl_source/
        wget https://ftp.openssl.org/source/openssl-1.1.1k.tar.gz

        cd $GIT_CLONE_SGXSSL/Linux
        make all
        if [[ "$OS" == "rhel" &&  "$VER" == "8.2" ]]; then
                make install || exit 1
        elif [[ "$OS" == "ubuntu" && "$VER" == "18.04" ]]; then
                sudo make install
        else
                echo "Unsupported OS. Please use RHEL 8.2 or Ubuntu 18.04"
                exit 1
        fi
        popd

        \cp -rpf $SGXSSL_PREFIX $SAMPLEAPPS_DIR
}

check_prerequisites()
{
        if [ ! -f /opt/intel/sgxsdk/bin/x64/sgx_edger8r ];then
                echo "sgx sdk is required for building sgxssl."
                exit 1
        fi
}

check_prerequisites
install_sgxssl

