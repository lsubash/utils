/*
 * Copyright (C) 2020 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
package config

import (
	"crypto/x509"
	"errors"
	"os"
	"path"
	"strconv"
	"time"

	errorLog "github.com/pkg/errors"
	commLog "intel/isecl/lib/common/v3/log"
	"intel/isecl/lib/common/v3/setup"
	"intel/isecl/sgx_agent/v3/constants"

	log "github.com/sirupsen/logrus"
	"gopkg.in/yaml.v3"
)

var slog = commLog.GetSecurityLogger()

// Configuration is the global configuration struct that is marshalled/unmarshaled to a persisted yaml file
// Probably should embed a config generic struct
type Configuration struct {
	configFile       string
	Port             int
	CmsTlsCertDigest string
	LogMaxLength     int
	LogEnableStdout  bool
	LogLevel         log.Level

	KeyAlgorithm       string
	KeyAlgorithmLength int
	CACertValidity     int
	TokenDurationMins  int

	SGX_AgentUserName string
	SGX_AgentPassword string
	CMSBaseUrl        string
	AuthServiceUrl    string
	SGXHVSBaseUrl     string
	SVSBaseURL        string
	ScsBaseUrl        string
	Subject           struct {
		TLSCertCommonName string
	}
	TLSKeyFile        string
	TLSCertFile       string
	CertSANList       string
	ReadTimeout       time.Duration
	ReadHeaderTimeout time.Duration
	WriteTimeout      time.Duration
	IdleTimeout       time.Duration
	MaxHeaderBytes    int

	TrustedRootCA *x509.Certificate
	NumberOfHosts int
	HostStartId   int
	SGXAgentMode  string
	WaitTime      int
	RetryCount    int
}

var global *Configuration

func Global() *Configuration {
	log.Trace("config/config:Global() Entering")
	defer log.Trace("config/config:Global() Leaving")

	if global == nil {
		global = Load(path.Join(constants.ConfigDir, constants.ConfigFile))
	}
	return global
}

func (conf *Configuration) SaveConfiguration(c setup.Context) error {
	log.Trace("config/config:SaveConfiguration() Entering")
	defer log.Trace("config/config:SaveConfiguration() Leaving")

	var err error = nil

	sgx_agentUserName, err := c.GetenvString("SGX_AGENT_USERNAME", "SGX_AGENT Username")
	if err == nil && sgx_agentUserName != "" {
		conf.SGX_AgentUserName = sgx_agentUserName
	} else if conf.SGX_AgentUserName == "" {
		log.Error("SGX_AGENT_USERNAME is not defined in environment")
	}

	sgx_agentPssword, err := c.GetenvString("SGX_AGENT_PASSWORD", "SGX_AGENT Password")
	if err == nil && sgx_agentPssword != "" {
		conf.SGX_AgentPassword = sgx_agentPssword
	} else if conf.SGX_AgentPassword == "" {
		log.Error("SGX_AGENT_PASSWORD is not defined in environment")
	}

	tlsCertDigest, err := c.GetenvString(constants.CmsTlsCertDigestEnv, "TLS certificate digest")
	if err == nil && tlsCertDigest != "" {
		conf.CmsTlsCertDigest = tlsCertDigest
	} else if conf.CmsTlsCertDigest == "" {
		commLog.GetDefaultLogger().Error("CMS_TLS_CERT_SHA384 is not defined in environment")
		return errorLog.Wrap(errors.New("CMS_TLS_CERT_SHA384 is not defined in environment"), "SaveConfiguration() ENV variable not found")
	}

	cmsBaseUrl, err := c.GetenvString("CMS_BASE_URL", "CMS Base URL")
	if err == nil && cmsBaseUrl != "" {
		conf.CMSBaseUrl = cmsBaseUrl
	} else if conf.CMSBaseUrl == "" {
		commLog.GetDefaultLogger().Error("CMS_BASE_URL is not defined in environment")
		return errorLog.Wrap(errors.New("CMS_BASE_URL is not defined in environment"), "SaveConfiguration() ENV variable not found")
	}

	aasApiUrl, err := c.GetenvString("AAS_API_URL", "AAS API URL")
	if err == nil && aasApiUrl != "" {
		conf.AuthServiceUrl = aasApiUrl
	} else if conf.AuthServiceUrl == "" {
		commLog.GetDefaultLogger().Error("AAS_API_URL is not defined in environment")
		return errorLog.Wrap(errors.New("AAS_API_URL is not defined in environment"), "SaveConfiguration() ENV variable not found")
	}

	sgxHVSBaseUrl, err := c.GetenvString("SHVS_BASE_URL", "HVS Base URL")
	if err == nil && sgxHVSBaseUrl != "" {
		conf.SGXHVSBaseUrl = sgxHVSBaseUrl
	} else if conf.SGXHVSBaseUrl == "" {
		log.Error("SHVS_BASE_URL is not defined in environment")
	}

	scsBaseUrl, err := c.GetenvString("SCS_BASE_URL", "SCS Base URL")
	if err == nil && scsBaseUrl != "" {
		conf.ScsBaseUrl = scsBaseUrl
	} else if conf.ScsBaseUrl == "" {
		log.Error("SCS_BASE_URL  is not defined in environment")
	}

	logLevel, err := c.GetenvString("SGX_AGENT_LOGLEVEL", "SGX_AGENT Log Level")
	if err != nil {
		slog.Infof("config/config:SaveConfiguration() %s not defined, using default log level: Info", constants.SGXAgentLogLevel)
		conf.LogLevel = log.InfoLevel
	} else {
		llp, err := log.ParseLevel(logLevel)
		if err != nil {
			slog.Info("config/config:SaveConfiguration() Invalid log level specified in env, using default log level: Info")
			conf.LogLevel = log.InfoLevel
		} else {
			conf.LogLevel = llp
			slog.Infof("config/config:SaveConfiguration() Log level set %s\n", logLevel)
		}
	}

	tlsCertCN, err := c.GetenvString("SGX_AGENT_TLS_CERT_CN", "SGX_AGENT TLS Certificate Common Name")
	if err == nil && tlsCertCN != "" {
		conf.Subject.TLSCertCommonName = tlsCertCN
	} else if conf.Subject.TLSCertCommonName == "" {
		conf.Subject.TLSCertCommonName = constants.DefaultSGX_AgentTlsCn
	}

	tlsKeyPath, err := c.GetenvString("KEY_PATH", "Path of file where TLS key needs to be stored")
	if err == nil && tlsKeyPath != "" {
		conf.TLSKeyFile = tlsKeyPath
	} else if conf.TLSKeyFile == "" {
		conf.TLSKeyFile = constants.DefaultTLSKeyFile
	}

	tlsCertPath, err := c.GetenvString("CERT_PATH", "Path of file/directory where TLS certificate needs to be stored")
	if err == nil && tlsCertPath != "" {
		conf.TLSCertFile = tlsCertPath
	} else if conf.TLSCertFile == "" {
		conf.TLSCertFile = constants.DefaultTLSCertFile
	}

	sanList, err := c.GetenvString("SAN_LIST", "SAN list for TLS")
	if err == nil && sanList != "" {
		conf.CertSANList = sanList
	} else if conf.CertSANList == "" {
		conf.CertSANList = constants.DefaultTlsSan
	}
	numberOfHosts, err := c.GetenvString("HOST_COUNT", "Number of  Hosts")
	if err == nil && numberOfHosts != "" {
		conf.NumberOfHosts, err = strconv.Atoi(numberOfHosts)
	} else if conf.NumberOfHosts == 0 {
		conf.NumberOfHosts = constants.NumberOfHosts
	}
	hostStartId, err := c.GetenvString("HOST_START_ID", "Hosts Starts from")
        if err == nil && hostStartId != "" {
                conf.HostStartId, err = strconv.Atoi(hostStartId)
        } else if conf.HostStartId == 0 {
                conf.HostStartId = constants.DefaultHostStartId
        }

	sgx_agent_mode, err := c.GetenvString("SGX_AGENT_MODE", "SGX Agent Mode")
	if err == nil && sgx_agent_mode != "" {
		conf.SGXAgentMode = sgx_agent_mode
	} else {
		conf.SGXAgentMode = constants.DefaultSgxAgentMode
	}

	waittime, err := c.GetenvInt("WAIT_TIME", "time between each retries to PCS")
	if err == nil {
		if waittime > constants.DefaultWaitTime {
			conf.WaitTime = waittime
		} else {
			conf.WaitTime = constants.DefaultWaitTime
		}
	} else {
		conf.WaitTime = constants.DefaultWaitTime
	}

	retrycount, err := c.GetenvInt("RETRY_COUNT", "Push Data Retry Count to SCS")
	if err == nil {
		if retrycount > constants.DefaultRetryCount {
			conf.RetryCount = retrycount
		} else {
			conf.RetryCount = constants.DefaultRetryCount
		}
	} else {
		conf.RetryCount = constants.DefaultRetryCount
	}

	return conf.Save()
}

func (c *Configuration) Save() error {
	log.Trace("config/config:Save() Entering")
	defer log.Trace("config/config:Save() Leaving")

	if c.configFile == "" {
		return errors.New("no config file")
	}
	file, err := os.OpenFile(c.configFile, os.O_RDWR, 0)
	if err != nil {
		// we have an error
		if os.IsNotExist(err) {
			// error is that the config doesnt yet exist, create it
			file, err = os.OpenFile(c.configFile, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
			if err != nil {
				return err
			}
		} else {
			// someother I/O related error
			return err
		}
	}
	defer func() {
		derr := file.Close()
		if derr != nil {
			log.WithError(derr).Error("Failed to flush config.yml")
		}
	}()

	return yaml.NewEncoder(file).Encode(c)
}

func Load(path string) *Configuration {
	log.Trace("config/config:Load() Entering")
	defer log.Trace("config/config:Load() Leaving")

	var c Configuration
	file, err := os.Open(path)
	if file != nil {
		defer func() {
			derr := file.Close()
			if derr != nil {
				log.WithError(derr).Error("Failed to close config.yml")
			}
		}()
		err = yaml.NewDecoder(file).Decode(&c)
		if err != nil {
			log.WithError(err).Error("Failed to decode config.yml contents")
		}

	} else {
		c.LogLevel = log.InfoLevel
	}

	c.configFile = path
	return &c
}
