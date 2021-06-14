/*
 * Copyright (C) 2021 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
package commands

import (
	"fmt"
	"io"
	"strings"

	"intel/isecl/lib/platform-info/v3/platforminfo"

	"github.com/pkg/errors"
)

const defaultIndent = 4

func printWithIndent(w io.Writer, i int, msg string) {
	indentStr := strings.Repeat(" ", i)
	fmt.Fprintln(w, indentStr+msg)
}

func PlatFormInfoTest(w io.Writer) error {
	platformInfoStruct, err := platforminfo.GetPlatformInfo()
	if err != nil {
		err = errors.Wrap(err, "failed to retrieve platform info")
		fmt.Fprintln(w, "HOST INFO...FAILED")
		printWithIndent(w, defaultIndent, "Error: "+err.Error())
		return err
	}
	fmt.Fprintln(w, "HOST INFO...PASSED")

	// print general info
	printWithIndent(w, defaultIndent, "OS: "+platformInfoStruct.OSName+" "+platformInfoStruct.OSVersion)
	printWithIndent(w, defaultIndent, "BIOS: "+platformInfoStruct.BiosName+" "+platformInfoStruct.BiosVersion)
	printWithIndent(w, defaultIndent, "CPU ID: "+platformInfoStruct.ProcessorInfo)
	printWithIndent(w, defaultIndent, "System UUID: "+platformInfoStruct.HardwareUUID)

	// print hardware feature
	if platformInfoStruct.HardwareFeatures.TXT.Enabled {
		printWithIndent(w, defaultIndent, "TXT: Enabled")
	} else {
		printWithIndent(w, defaultIndent, "TXT: Disabled")
	}
	if platformInfoStruct.HardwareFeatures.CBNT != nil {
		if platformInfoStruct.HardwareFeatures.CBNT.Enabled {
			printWithIndent(w, defaultIndent, "BootGuard: Enabled")
			printWithIndent(w, defaultIndent, "BootGuard Profile: "+platformInfoStruct.HardwareFeatures.CBNT.Meta.Profile)
		} else {
			printWithIndent(w, defaultIndent, "BootGuard: Disabled")
		}
	}
	if platformInfoStruct.HardwareFeatures.SUEFI != nil {
		if platformInfoStruct.HardwareFeatures.SUEFI.Enabled {
			printWithIndent(w, defaultIndent, "SecureUEFI: Enabled")
		} else {
			printWithIndent(w, defaultIndent, "SecureUEFI: Disabled")
		}
	}
	// detect SGX
	sgx_value := isSGXInstructionSetSuported()
	if sgx_value == 0 {
		printWithIndent(w, defaultIndent, "SGX: not_supported")
	}
	if sgx_value == 1 {
		printWithIndent(w, defaultIndent, "SGX: sgx_1_supported")
	}
	if sgx_value == 2 {
		printWithIndent(w, defaultIndent, "SGX: sgx_2_supported")
	}
	return nil
}

func CheckTrustedBoot(w io.Writer) (bool, error) {
	pInfo, err := platforminfo.GetPlatformInfo()
	if err != nil {
		return false, errors.Wrap(err, "failed to retrieve platform info")
	}
	if !pInfo.TPMEnabled {
		fmt.Fprintln(w, "Trusted Boot...FAILED")
		printWithIndent(w, defaultIndent, "TPM not enabled")
		return false, nil
	}
	var txt, bootGuard, suefi, tboot bool
	txt = pInfo.TXTEnabled
	tboot = pInfo.TbootInstalled
	if pInfo.HardwareFeatures.CBNT != nil {
		bootGuard = pInfo.HardwareFeatures.CBNT.Enabled
	}
	if pInfo.HardwareFeatures.SUEFI != nil {
		suefi = pInfo.HardwareFeatures.SUEFI.Enabled
	}
	trustedBootPass := false
	if txt {
		trustedBootPass = tboot || suefi
	} else {
		trustedBootPass = bootGuard && suefi
	}
	var opt []string
	if txt {
		opt = append(opt, "TXT")
	}
	if bootGuard {
		opt = append(opt, "Boot Guard")
	}
	if tboot {
		opt = append(opt, "tboot")
	}
	if suefi {
		opt = append(opt, "SUEFI")
	}
	if trustedBootPass {
		fmt.Fprintln(w, "Trusted Boot...PASSED")
		printWithIndent(w, defaultIndent, "Trusted boot configuration: "+strings.Join(opt, ", "))
	} else {
		fmt.Fprintln(w, "Trusted Boot...FAILED")
		printWithIndent(w, defaultIndent, "Detected configuration is invalid: "+strings.Join(opt, ", "))
	}
	return trustedBootPass, nil
}

func PlatFormInfoTPM() (bool, string, []string, error) {
	pInfo, err := platforminfo.GetPlatformInfo()
	if err != nil {
		return false, "", nil, errors.Wrap(err, "failed to retrieve platform info")
	}
	return pInfo.TPMEnabled, pInfo.TPMVersion, []string{"SHA1", "SHA256"}, nil
}
