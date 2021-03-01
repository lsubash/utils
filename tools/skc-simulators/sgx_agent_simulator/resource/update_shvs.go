/*
* Copyright (C) 2020 Intel Corporation
* SPDX-License-Identifier: BSD-3-Clause
 */
package resource

import (
	"github.com/pkg/errors"

	"intel/isecl/lib/clients/v3"
	"intel/isecl/sgx_agent/v3/config"
	"intel/isecl/sgx_agent/v3/constants"
	"intel/isecl/sgx_agent/v3/utils"

	"bytes"
	"encoding/json"
	"io/ioutil"
	"net/http"
	"strconv"
	"time"
)

var (
	hardwareUUIDCmd = []string{"dmidecode", "-s", "system-uuid"}
)

// UpdateSHVSPeriodically Updates SHVS periodically. If an error occurs,
// error is logged and wait for the next update.
func UpdateSHVSPeriodically(sgxdiscovery *SGXDiscoveryData, platformData *PlatformData, period int) error {
	// update SHVS as per configured timer.
	for {
		conf := config.Global()
		if conf == nil {
			return errors.Wrap(errors.New("pushHostSGXDiscovery: Configuration pointer is null"), "Config error")
		}

		for i := conf.HostStartId; i < conf.HostStartId+conf.NumberOfHosts; i++ {
			ExtractSGXPlatformValues(i)
			tcbstatus, err := GetTCBStatus(platformData.QeID)
			if err != nil {
				// Log error . But don't throw it.
				log.WithError(err).Error("Unable to get TCB Status from SCS.")
			} else {
				tcbUptoDate, _ := strconv.ParseBool(tcbstatus)
				err = PushSGXEnablementData(sgxdiscovery, tcbUptoDate)
				if err != nil {
					// Log error . But don't throw it.
					log.WithError(err).Error("Unable to update SHVS.")
				}
			}
		}
		// Sleep here on a timer.
		log.Infof("Waiting for %v minutes until next update.", period)
		time.Sleep(time.Duration(period) * time.Minute)
	}
}

type SGXHostInfo struct {
	HostName     string `json:"host_name"`
	Description  string `json:"description,omitempty"`
	UUID         string `json:"uuid"`
	SgxSupported bool   `json:"sgx_supported"`
	SgxEnabled   bool   `json:"sgx_enabled"`
	FlcEnabled   bool   `json:"flc_enabled"`
	EpcOffset    string `json:"epc_offset"`
	EpcSize      string `json:"epc_size"`
	TcbUptodate  bool   `json:"tcb_upToDate"`
}

// PushSGXEnablementDataRepeatUntilSuccess is a Wrapper over PushHostSGXDiscovery
// Retries in case of error till we succeed.
func PushSGXEnablementDataRepeatUntilSuccess(sgxdiscovery *SGXDiscoveryData, tcbstatus bool) error {
	conf := config.Global()
	if conf == nil {
		return errors.Wrap(errors.New("pushHostSGXDiscovery: Configuration pointer is null"), "Config error")
	}

	err := PushSGXEnablementData(sgxdiscovery, tcbstatus)

	var timeBwCalls int = conf.WaitTime
	var retries int = 0
	if err != nil {
		log.WithError(err)
		for {
			err = PushSGXEnablementData(sgxdiscovery, tcbstatus)
			if err == nil {
				return nil // Exit out of this loop
			}

			retries++
			if retries >= conf.RetryCount {
				log.Errorf("pushHostSGXDiscovery: Retried %d times, Sleeping %d minutes...", conf.RetryCount, timeBwCalls)
				time.Sleep(time.Duration(timeBwCalls) * time.Minute)
				retries = 0
			}
		}
	}
	return err
}

// PushSGXEnablementData updates SHVS With SGX Discovery Data and TCB Status.
func PushSGXEnablementData(sgxdiscovery *SGXDiscoveryData, tcbstatus bool) error {
	log.Trace("resource/update_shvs:PushHostSGXDiscovery Entering")
	defer log.Trace("resource/update_shvs:PushHostSGXDiscovery Leaving")

	conf := config.Global()
	if conf == nil {
		return errors.Wrap(errors.New("UpdateHostSGXDiscovery: Configuration pointer is null"), "Config error")
	}

	apiEndPoint := conf.SGXHVSBaseURL + "/hosts"
	log.Debug("Updating SGX Discovery data to SHVS at ", apiEndPoint)

	for i := conf.HostStartId; i < conf.HostStartId+conf.NumberOfHosts; i++ {
		ExtractSGXPlatformValues(i)
		//Hardware UUID
		id_str := strconv.Itoa(i)
		hostName := "sgxagent" + id_str

		for len(id_str) < 5 {
			id_str = "0" + id_str
		}
		hardwareUUID := "d7102665-88c9-46da-85c8-6a5a" + id_str + "e08"

		description := "Demo" + id_str
		requestData := SGXHostInfo{
			HostName:     hostName,
			Description:  description,
			UUID:         hardwareUUID,
			SgxSupported: sgxdiscovery.SgxSupported,
			SgxEnabled:   sgxdiscovery.SgxEnabled,
			FlcEnabled:   sgxdiscovery.FlcEnabled,
			EpcOffset:    sgxdiscovery.EpcStartAddress,
			EpcSize:      sgxdiscovery.EpcSize,
			TcbUptodate:  true}

		reqBytes, err := json.Marshal(requestData)
		if err != nil {
			return errors.Wrap(err, "UpdateHostSGXDiscovery: struct to json marshalling failed")
		}

		request, _ := http.NewRequest("POST", apiEndPoint, bytes.NewBuffer(reqBytes))
		request.Header.Set("Content-Type", "application/json")
		err = utils.AddJWTToken(request)
		if err != nil {
			return errors.Wrap(err, "UpdateHostSGXDiscovery: Failed to add JWT token to the authorization header")
		}

		client, err := clients.HTTPClientWithCADir(constants.TrustedCAsStoreDir)
		if err != nil {
			log.WithError(err).Error("resource/update_shvs:UpdateHOSTSGXDiscovery() Error while creating http client")
			return errors.Wrap(err, "resource/update_shvs:UpdateHOSTSGXDiscovery() Error while creating http client")
		}

		httpClient := &http.Client{
			Transport: client.Transport,
		}

		response, err := httpClient.Do(request)

		if response != nil && response.StatusCode == http.StatusUnauthorized {
			// Token could have expired. Fetch token and try again
			utils.AasRWLock.Lock()
			err = utils.AasClient.FetchAllTokens()
			if err != nil {
				return errors.Wrap(err, "PushSGXEnablementData: FetchAllTokens() Could not fetch token")
			}
			utils.AasRWLock.Unlock()
			err = utils.AddJWTToken(request)
			if err != nil {
				return errors.Wrap(err, "PushSGXEnablementData: Failed to add JWT token to the authorization header")
			}

			request.Body = ioutil.NopCloser(bytes.NewBuffer(reqBytes))
			response, err = httpClient.Do(request)
		}

		if response != nil {
			defer func() {
				derr := response.Body.Close()
				if derr != nil {
					log.WithError(derr).Error("Error closing response")
				}
			}()
		}
		if err != nil {
			slog.WithError(err).Error("resource/UpdateHostSGXDiscovery Error making request")
			return errors.Wrapf(err, "resource/UpdateHostSGXDiscovery Error making request %s", apiEndPoint)
		}

		log.Debug("Request Completed : ", response.StatusCode)

		if (response.StatusCode != http.StatusOK) && (response.StatusCode != http.StatusCreated) {
			return errors.Errorf("resource/UpdateHostSGXDiscovery Request made to %s returned status %d", apiEndPoint, response.StatusCode)
		}

		data, err := ioutil.ReadAll(response.Body)
		if err != nil {
			return errors.Wrap(err, "resource/UpdateHostSGXDiscovery Error reading response")
		}

		log.Debugf("Response from SHVS: -%v", string(data))
	}
	return nil
}
