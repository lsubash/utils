/*
 * Copyright (C) 2020  Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
package constants

import "time"

const (
	HomeDir                   = "/opt/sgx_agent/"
	ConfigDir                 = "/etc/sgx_agent/"
	ExecutableDir             = "/opt/sgx_agent/bin/"
	ExecLinkPath              = "/usr/bin/sgx_agent"
	RunDirPath                = "/run/sgx_agent"
	LogDir                    = "/var/log/sgx_agent/"
	LogFile                   = LogDir + "sgx_agent.log"
	SecurityLogFile           = LogDir + "sgx_agent-security.log"
	HTTPLogFile               = LogDir + "http.log"
	ConfigFile                = "config.yml"
	NumberOfHosts             = 5
	TokenSignKeysAndCertDir   = ConfigDir + "certs/tokensign/"
	TokenSignCertFile         = TokenSignKeysAndCertDir + "jwtsigncert.pem"
	TrustedJWTSigningCertsDir = ConfigDir + "certs/trustedjwt/"
	TrustedCAsStoreDir        = ConfigDir + "certs/trustedca/"
	DefaultTLSCertFile        = ConfigDir + "tls-cert.pem"
	DefaultTLSKeyFile         = ConfigDir + "tls.key"
	CmsTLSCertDigestEnv       = "CMS_TLS_CERT_SHA384"
	SGXAgentLogLevel          = "SGX_AGENT_LOGLEVEL"
	DefaultReadTimeout        = 30 * time.Second
	DefaultReadHeaderTimeout  = 10 * time.Second
	DefaultWriteTimeout       = 10 * time.Second
	DefaultIdleTimeout        = 10 * time.Second
	DefaultMaxHeaderBytes     = 1 << 20
	DefaultLogEntryMaxLength  = 300
	ServiceRemoveCmd          = "systemctl disable sgx_agent"
	ServiceName               = "SGX_AGENT"
	HostDataReaderGroupName   = "HostDataReader"
	SGXAgentUserName          = "sgx_agent"
	DefaultTokenDurationMins  = 240
	DefaultHTTPSPort          = 11001
	DefaultKeyAlgorithm       = "rsa"
	DefaultKeyAlgorithmLength = 3072
	DefaultTLSSan             = "127.0.0.1,localhost"
	DefaultSGXAgentTLSCn      = "SGX_AGENT TLS Certificate"
	CertApproverGroupName     = "CertApprover"
	DefaultRootCACommonName   = "SGX_AGENTCA"
	DefaultWaitTime           = 5
	DefaultRetryCount         = 5
	DefaultSHVSUpdateInterval = 1
	DefaultHostStartId        = 1
)
