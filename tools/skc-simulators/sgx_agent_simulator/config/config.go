/*
 * Copyright (C) 2020  Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
package config

import (
	"crypto/x509"
	"errors"
	"os"
	"path"
	"time"

	errorLog "github.com/pkg/errors"
	commLog "intel/isecl/lib/common/v3/log"
	"intel/isecl/lib/common/v3/setup"
	"intel/isecl/sgx_agent/v3/constants"

	log "github.com/sirupsen/logrus"
	"gopkg.in/yaml.v3"
	"strconv"
)

var slog = commLog.GetSecurityLogger()

// Configuration is the global configuration struct that is marshalled/unmarshaled to a persisted yaml file
// Probably should embed a config generic struct
type Configuration struct {
	configFile       string
	Port             int
	CmsTLSCertDigest string
	LogMaxLength     int
	LogEnableStdout  bool
	LogLevel         log.Level

	KeyAlgorithm       string
	KeyAlgorithmLength int
	CACertValidity     int
	TokenDurationMins  int

	SGXAgentUserName string
	SGXAgentPassword string
	CMSBaseURL       string
	AuthServiceURL   string
	SGXHVSBaseURL    string
	SVSBaseURL       string
	ScsBaseURL       string
	Subject          struct {
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

	TrustedRootCA      *x509.Certificate
	NumberOfHosts      int
	HostStartId        int
	WaitTime           int
	RetryCount         int
	SHVSUpdateInterval int
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

	sgxAgentUserName, err := c.GetenvString("SGX_AGENT_USERNAME", "SGX_AGENT Username")
	if err == nil && sgxAgentUserName != "" {
		conf.SGXAgentUserName = sgxAgentUserName
	} else if conf.SGXAgentUserName == "" {
		log.Error("SGX_AGENT_USERNAME is not defined in environment")
	}

	sgxAgentPassword, err := c.GetenvString("SGX_AGENT_PASSWORD", "SGX_AGENT Password")
	if err == nil && sgxAgentPassword != "" {
		conf.SGXAgentPassword = sgxAgentPassword
	} else if conf.SGXAgentPassword == "" {
		log.Error("SGX_AGENT_PASSWORD is not defined in environment")
	}

	tlsCertDigest, err := c.GetenvString(constants.CmsTLSCertDigestEnv, "TLS certificate digest")
	if err == nil && tlsCertDigest != "" {
		conf.CmsTLSCertDigest = tlsCertDigest
	} else if conf.CmsTLSCertDigest == "" {
		commLog.GetDefaultLogger().Error("CMS_TLS_CERT_SHA384 is not defined in environment")
		return errorLog.Wrap(errors.New("CMS_TLS_CERT_SHA384 is not defined in environment"), "SaveConfiguration() ENV variable not found")
	}

	cmsBaseURL, err := c.GetenvString("CMS_BASE_URL", "CMS Base URL")
	if err == nil && cmsBaseURL != "" {
		conf.CMSBaseURL = cmsBaseURL
	} else if conf.CMSBaseURL == "" {
		commLog.GetDefaultLogger().Error("CMS_BASE_URL is not defined in environment")
		return errorLog.Wrap(errors.New("CMS_BASE_URL is not defined in environment"), "SaveConfiguration() ENV variable not found")
	}

	aasAPIURL, err := c.GetenvString("AAS_API_URL", "AAS API URL")
	if err == nil && aasAPIURL != "" {
		conf.AuthServiceURL = aasAPIURL
	} else if conf.AuthServiceURL == "" {
		commLog.GetDefaultLogger().Error("AAS_API_URL is not defined in environment")
		return errorLog.Wrap(errors.New("AAS_API_URL is not defined in environment"), "SaveConfiguration() ENV variable not found")
	}

	sgxHVSBaseURL, err := c.GetenvString("SHVS_BASE_URL", "HVS Base URL")
	if err == nil && sgxHVSBaseURL != "" {
		conf.SGXHVSBaseURL = sgxHVSBaseURL
	} else if conf.SGXHVSBaseURL == "" {
		log.Info("SHVS_BASE_URL is not defined in environment. ")
	}

	scsBaseURL, err := c.GetenvString("SCS_BASE_URL", "SCS Base URL")
	if err == nil && scsBaseURL != "" {
		conf.ScsBaseURL = scsBaseURL
	} else if conf.ScsBaseURL == "" {
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
		conf.Subject.TLSCertCommonName = constants.DefaultSGXAgentTLSCn
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
		conf.CertSANList = constants.DefaultTLSSan
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

	waittime, err := c.GetenvInt("WAIT_TIME", "1 time between each retries to PCS")
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

	shvsUpdateInterval, err := c.GetenvInt("SHVS_UPDATE_INTERVAL", "SHVS update interval in minutes")
	if err == nil {
		if shvsUpdateInterval > 0 && shvsUpdateInterval <= constants.DefaultSHVSUpdateInterval {
			conf.SHVSUpdateInterval = shvsUpdateInterval
			log.Info("SHVS Update interval is out of range 1 < SHVSUpdateInterval < 120 . Using default value of 120 minutes")
		} else {
			conf.SHVSUpdateInterval = constants.DefaultSHVSUpdateInterval
		}
	} else {
		conf.SHVSUpdateInterval = constants.DefaultSHVSUpdateInterval
	}

	return conf.Save()
}

func (conf *Configuration) Save() error {
	log.Trace("config/config:Save() Entering")
	defer log.Trace("config/config:Save() Leaving")

	if conf.configFile == "" {
		return errors.New("no config file")
	}
	file, err := os.OpenFile(conf.configFile, os.O_RDWR, 0)
	if err != nil {
		// we have an error
		if os.IsNotExist(err) {
			// error is that the config doesnt yet exist, create it
			file, err = os.OpenFile(conf.configFile, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
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

	return yaml.NewEncoder(file).Encode(conf)
}

func Load(filePath string) *Configuration {
	log.Trace("config/config:Load() Entering")
	defer log.Trace("config/config:Load() Leaving")

	var c Configuration
	file, _ := os.Open(filePath)
	if file != nil {
		defer func() {
			derr := file.Close()
			if derr != nil {
				log.WithError(derr).Error("Failed to close config.yml")
			}
		}()
		err := yaml.NewDecoder(file).Decode(&c)
		if err != nil {
			log.WithError(err).Error("Failed to decode config.yml contents")
		}

	} else {
		c.LogLevel = log.InfoLevel
	}

	c.configFile = filePath
	return &c
}
