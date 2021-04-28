#!/bin/bash

modprobe -n intel_sgx 2>/dev/null
DRIVER_LOADED=$?
echo "$DRIVER_LOADED"
