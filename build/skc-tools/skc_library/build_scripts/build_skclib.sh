#!/bin/bash
SKCLIB_DIR=$PWD/skc_library
SKCLIB_BIN_DIR=$SKCLIB_DIR/bin
SKCLIB_VERSION=4.0

build_skc_library()
{
	pushd $PWD

	cd ../../../../../skc_library
	./scripts/build.sh
	if [ $? -ne 0 ]; then
		echo "ERROR: skc_library build failed with $?"
		exit 1
	fi

	./scripts/generate_bin.sh $SKCLIB_VERSION
	if [ $? -ne 0 ]; then
                echo "ERROR: skc_library binary generation failed with $?"
                exit 1
        fi
	
	mkdir -p $SKCLIB_BIN_DIR
	\cp -pf skc_library_v*.bin $SKCLIB_BIN_DIR
	popd
	if [ "$OS" == "rhel" ]; then
		\cp -pf /usr/lib64/engines-1.1/pkcs11.so $SKCLIB_BIN_DIR
		\cp -pf /usr/lib64/libp11.so.3.4.3 $SKCLIB_BIN_DIR
	elif [ "$OS" == "ubuntu" ]; then
		\cp -pf /usr/lib/x86_64-linux-gnu/engines-1.1/pkcs11.so $SKCLIB_BIN_DIR
	        \cp -pf /usr/lib/libp11.so.3.4.3 $SKCLIB_BIN_DIR
	fi
}

build_skc_library
