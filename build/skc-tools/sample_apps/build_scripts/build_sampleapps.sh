#!/bin/bash

SAMPLEAPPS_DIR=sample_apps
SAMPLEAPPS_BIN_DIR=$SAMPLEAPPS_DIR/bin

build_sample_apps()
{
	pushd $PWD

	cd ../../../../../utils/tools/sample-sgx-attestation
        touch rootca.pem
	make all
	if [ $? -ne 0 ]; then
		echo "ERROR: sample apps build failed with $?"
		exit 1
	fi

	mkdir -p $SAMPLEAPPS_BIN_DIR
	popd

	if [ "$OS" == "rhel" ]; then
		\cp -pf /usr/lib64/engines-1.1/pkcs11.so $SAMPLEAPPS_BIN_DIR
		\cp -pf /usr/lib64/libp11.so.3.4.3 $SAMPLEAPPS_BIN_DIR
	elif [ "$OS" == "ubuntu" ]; then
		\cp -pf /usr/lib/x86_64-linux-gnu/engines-1.1/pkcs11.so $SAMPLEAPPS_BIN_DIR
	        \cp -pf /usr/lib/libp11.so.3.4.3 $SAMPLEAPPS_BIN_DIR
	fi
}
build_sample_apps
