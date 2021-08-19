#!/bin/bash
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
	
	\cp -pf skc_library_v*.bin $SKCLIB_BIN_DIR
	popd
	\cp -pf $LIB_DIR/engines-1.1/pkcs11.so $SKCLIB_BIN_DIR
	\cp -pf $LIB_DIR/libp11.so.* $SKCLIB_BIN_DIR
}

build_skc_library
