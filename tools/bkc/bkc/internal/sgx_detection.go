/*
 * Copyright (C) 2021 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
package commands

import (
	"io/ioutil"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"github.com/klauspost/cpuid"

	"github.com/pkg/errors"
)

// this is the trimmed down version of:
// https://github.com/intel-secl/sgx_agent/blob/master/resource/sgx_detection.go

var (
	flcEnabledCmd      = []string{"rdmsr", "-ax", "0x3A"} ///MSR.IA32_Feature_Control register tells availability of SGX
	pckIDRetrievalInfo = []string{"PCKIDRetrievalTool", "-f", "/opt/pckData"}
)

///This is done in TA but we might need to do here
func isSGXEnabled() (bool, error) {
	result, err := readAndParseFromCommandLine(flcEnabledCmd)
	if err != nil {
		return false, nil
	}
	sgxStatus := false
	registerValue := result[0]
	val, error := strconv.ParseInt(registerValue, 16, 64)
	if error != nil {
		return false, nil
	}

	if (((val >> 18) & 1) != 0) && ((val)&1 != 0) { ///18th bit stands for IA32_FEATURE_CONTROL. 0th bit should be set to 1.
		sgxStatus = true
	}
	return sgxStatus, err
}

func isFLCEnabled() (bool, error) {
	result, err := readAndParseFromCommandLine(flcEnabledCmd)
	if err != nil {
		return false, nil
	}
	sgxStatus := false
	registerValue := result[0]
	val, error := strconv.ParseInt(registerValue, 16, 64)
	if error != nil {
		return false, nil
	}
	if (((val >> 17) & 1) != 0) && ((val)&1 != 0) { ///17th bit stands for IA32_FEATURE_CONTROL. 0th bit should be ste to 1.
		sgxStatus = true
	}
	return sgxStatus, err
}

// this calls to asm code in cpuid_amd64.s
func cpuid_low(arg1, arg2 uint32) (eax, ebx, ecx, edx uint32)

func isCPUSupportsSGXExtensions() bool {
	sgx_extensions_enabled := false
	_, ebx, _, _ := cpuid_low(7, 0)
	if ((ebx >> 2) & 1) != 0 { ///2nd bit should be set if SGX extensions are supported.
		sgx_extensions_enabled = true
	}
	return sgx_extensions_enabled
}

func check(e error) {
	if e != nil {
		panic(e)
	}
}

func writePCKDetails() (string, error) {
	_, err := readAndParseFromCommandLine(pckIDRetrievalInfo)
	if err != nil {
		return "", err
	}
	fileContents := ""
	///check if file exists in the directory then parse it and write the values in log file.
	if _, err := os.Stat("/opt/pckData"); err == nil {
		// path/to/whatever exists
		dat, err := ioutil.ReadFile("/opt/pckData")
		check(err)
		fileContents = string(dat[:])
	} else if os.IsNotExist(err) {
		return "", errors.Wrap(err, "pckIDRetrievalInfo file not found")
	} else {
		return "", errors.Wrap(err, "pckIDRetrievalInfo file stat error")
	}
	return fileContents, err
}

func isSGXInstructionSetSuported() int {
	cpuid.Detect()
	sgx_value := 0
	if cpuid.CPU.SGX.SGX1Supported {
		sgx_value = 1
		if cpuid.CPU.SGX.SGX2Supported {
			sgx_value = 2
		}
	} else {
		return 0
	}
	return sgx_value
}

func maxEnclaveSize() (int64, int64) {
	cpuid.Detect()
	return cpuid.CPU.SGX.MaxEnclaveSizeNot64, cpuid.CPU.SGX.MaxEnclaveSize64
}

func readAndParseFromCommandLine(input []string) ([]string, error) {
	cmd := exec.Command(input[0], input[1:]...)
	out, err := cmd.CombinedOutput()
	result := strings.Split(string(out), "\n")
	cleanedResult := deleteEmptyFromSlice(result)
	return cleanedResult, err
}

func deleteEmptyFromSlice(s []string) []string {
	r := make([]string, 0)
	for i := range s {
		trimmed := strings.TrimSpace(s[i])
		if strings.HasPrefix(trimmed, "#") {
			continue
		}
		if trimmed != "" {
			r = append(r, trimmed)
		}
	}
	return r
}
