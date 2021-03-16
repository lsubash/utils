#!/bin/bash

SGX_AGENT_DIR=$PWD/sgx_agent
SGX_AGENT_BIN_DIR=$SGX_AGENT_DIR/bin

build_sgx_agent_docker()
{
	pushd $PWD
#	\cp -prf $SGX_AGENT_BIN_DIR ../../../../../sgx_agent/dist/image/
#	tar -xf ../../../../../sgx_agent/dist/image/bin/sgx_rpm_local_repo.tgz -C ../../../../../sgx_agent/dist/image/bin/
#	cd ../../../../../sgx_agent
#	make oci-archive || exit 1
#	rm -rf dist/image/bin
	popd
}

build_sgx_agent_docker
