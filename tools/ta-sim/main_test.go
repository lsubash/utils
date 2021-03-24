/*
 * Copyright (C) 2020  Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
package main

import (
	"testing"
)

func TestTASimulator(t *testing.T) {
	ac := AppConfig{
		PortStart:              10000,
		Servers:                3,
		DistinctFlavors:        2,
		QuoteDelayMs:           500,
		RequestVolume:          50,
		RequestVolumeDelayMs:   100,
		TrustedHostsPercentage: 99,
		sslCertPath:            "test/configuration/cert.pem",
		sslKeyPath:             "test/configuration/key.pem",
		tpmQuotePath:           "test/repository/quote.xml",
		hostInfoPath:           "test/repository/host_info.json",
		aikCertPath:            "test/configuration/aik.cert.pem",
		aikKeyPath:             "test/configuration/aik.key.pem",
		bindingKeyPath:         "test/repository/bk.cert",
		hwUuidMapPath:          "test/configuration/hw_uuid_map.json",
	}

	startServers(&ac)
}
