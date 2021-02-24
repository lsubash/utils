#!/bin/bash
SKCLIB_DIR=$PWD/skc_library
SKCLIB_BIN_DIR=$SKCLIB_DIR/bin
SKCLIB_VERSION=3.4

build_skc_library_docker()
{
	pushd $PWD
	\cp -prf $SKCLIB_DIR/cryptoapitoolkit ../../../../../skc_library/dist/image/
	\cp -prf $SKCLIB_DIR/sgxssl ../../../../../skc_library/dist/image/
	\cp -prf ../deploy_scripts/skc_library.conf ../../../../../skc_library/dist/image/
	\cp -prf $SKCLIB_BIN_DIR ../../../../../skc_library/dist/image/
	tar -xf ../../../../../skc_library/dist/image/bin/sgx_rpm_local_repo.tgz -C ../../../../../skc_library/dist/image/bin/
	cd ../../../../../skc_library
	make docker || exit 1
	\cp -pf skc-lib-*.tar $SKCLIB_BIN_DIR
	rm -rf dist/image/cryptoapitoolkit dist/image/sgxssl dist/image/bin dist/image/skc_library.conf
	popd
}

build_skc_library_docker
