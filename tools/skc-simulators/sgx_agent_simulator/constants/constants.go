/*
 * Copyright (C) 2020 Intel Corporation
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
	NumberOfHosts             = 10
	SerialNumberPath          = ConfigDir + "serial-number"
	TokenSignKeysAndCertDir   = ConfigDir + "certs/tokensign/"
	TokenSignCertFile         = TokenSignKeysAndCertDir + "jwtsigncert.pem"
	TrustedJWTSigningCertsDir = ConfigDir + "certs/trustedjwt/"
	TrustedCAsStoreDir        = ConfigDir + "certs/trustedca/"
	DefaultTLSCertFile        = ConfigDir + "tls-cert.pem"
	DefaultTLSKeyFile         = ConfigDir + "tls.key"
	JWTCertsCacheTime         = "60m"
	CmsTlsCertDigestEnv       = "CMS_TLS_CERT_SHA384"
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
	DefaultHttpPort           = 11001
	DefaultKeyAlgorithm       = "rsa"
	DefaultKeyAlgorithmLength = 3072
	DefaultTlsSan             = "127.0.0.1,localhost"
	DefaultSGX_AgentTlsCn     = "SGX_AGENT TLS Certificate"
	CertApproverGroupName     = "CertApprover"
	DefaultRootCACommonName   = "SGX_AGENTCA"
	RegistrationMode          = "Registration"
	DefaultSgxAgentMode       = "Orchestration"
	DefaultWaitTime           = 5
	DefaultRetryCount         = 5
	DefaultHostStartId	  = 1
)
