#!/bin/bash
source install_basic.sh
if [ $? -ne 0 ]
then
        echo "${red} SKC Basic components installation failed ${reset}"
        exit 1
fi

source install_orchestrator.sh
if [ $? -ne 0 ]
then
        echo "${red} SHVS/IHUB installation failed ${reset}"
        exit 1
fi
