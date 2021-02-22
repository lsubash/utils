#!/bin/bash
source install_basic.sh
if [ $? -ne 0 ]
then
        echo "skc basic component installation failed"
        exit
fi

source install_orchestrator.sh
if [ $? -ne 0 ]
then
        echo "SHVS/IHUB installation failed"
        exit
fi
