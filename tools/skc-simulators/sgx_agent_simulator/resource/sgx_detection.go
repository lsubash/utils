/*
 * Copyright (C) 2020 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

package resource

import (
	"bytes"
	"encoding/json"
	"github.com/pkg/errors"
	"intel/isecl/lib/clients/v3"
	clog "intel/isecl/lib/common/v3/log"
	"intel/isecl/sgx_agent/v3/config"
	"intel/isecl/sgx_agent/v3/constants"
	"intel/isecl/sgx_agent/v3/utils"
	"io/ioutil"
	"net/http"
	"strconv"
	"time"
)

var log = clog.GetDefaultLogger()
var slog = clog.GetSecurityLogger()

type SGXDiscoveryData struct {
	SgxSupported        bool   `json:"sgx-supported"`
	SgxEnabled          bool   `json:"sgx-enabled"`
	FlcEnabled          bool   `json:"flc-enabled"`
	EpcStartAddress     string `json:"epc-offset"`
	EpcSize             string `json:"epc-size"`
	sgxInstructionSet   int
	maxEnclaveSizeNot64 int64
	maxEnclaveSize64    int64
}

type PlatformData struct {
	EncryptedPPID string `json:"enc-ppid"`
	PceID         string `json:"pceid"`
	CPUSvn        string `json:"cpusvn"`
	PceSvn        string `json:"pcesvn"`
	QeID          string `json:"qeid"`
	Manifest      string `json:"Manifest"`
}

type SCSPushResponse struct {
	Status  string `json:"Status"`
	Message string `json:"Message"`
}

var sgxData SGXDiscoveryData
var platformData PlatformData

func ExtractSGXPlatformValues(id int) (*SGXDiscoveryData, *PlatformData, error) {
	var sgxEnablementInfo *SGXDiscoveryData
	var sgxPlatformData *PlatformData
	id_str := strconv.Itoa(id)
	log.Info("SGX Extensions are enabled, hence proceeding further")
	sgxData.SgxSupported = true
	sgxData.SgxEnabled = true
	sgxData.FlcEnabled = true
	sgxData.EpcStartAddress = "0x7020" + id_str
	sgxData.EpcSize = "189.5" + id_str + " MB"
	platformData.PceID = "0000"
	platformData.CPUSvn = "0202ffffff8002000000010000000000"
	platformData.PceSvn = "0a00"
	sgxData.EpcStartAddress = "0x7020" + id_str
	sgxData.EpcSize = "189.5" + id_str + " MB"
	for len(id_str) < 6 {
		id_str = "0" + id_str
	}

	platformData.EncryptedPPID = "d029c0e96cbcd22918f54329b89ec624eb851860395f56dd88125013ca4651e6f263e925c3f40ad2b498697583effffe55ee641c4f3fd3ffce963e86a6d3b830a833b48a5714bd4229612c2f92c62c7becd6b0e39e5b830b95f484b3c23a3c4d1eb3f8ea0e6978e50151853baba19a2b58ecda921b5eb2b92524e158960f068ece55da722cc6d166e44b2ee0a6cebf9733bf2f3df46016373d14b5ec7e1b270d99aaa06cc38112adc7259a86ef4965907832933c2258cfefee165fd64dddea283ab9f6864639bf58c240de57746ae7e62ddd1917978bce6f42dd39e8ab733b58037dcc2230c0a873d5d0f257c714e8b05133879e1f4422427872c99715dfd5bf82325d4d0307347a3f36b21f58e96f73311f88cb207dc1bd4bafe444b23988641c9c7f45905c6b7c902d5841a07b2360a24010108beb7ec809941909b45375b51afa0626af7733c7eb4144cbc08cb4fb47477c1193955844263cae04c6b6e93be0992c157aa08866a56262746cb8c9e65787ce8d649cc2cb0d939f42ffec937a"
	platformData.QeID = "bf2b" + id_str + "b1bb879a788a1c104f67ff"
	platformData.Manifest = "qwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnmqwertyuiopasdfghjklzxcvbnm"
	sgxEnablementInfo = &sgxData
	sgxPlatformData = &platformData
	return sgxEnablementInfo, sgxPlatformData, nil
}

func PushSGXData(pdata *PlatformData, hardwareUUID string) (bool, error) {
	log.Trace("resource/sgx_detection.go: PushSGXData() Entering")
	defer log.Trace("resource/sgx_detection.go: PushSGXData() Leaving")
	client, err := clients.HTTPClientWithCADir(constants.TrustedCAsStoreDir)
	if err != nil {
		return false, errors.Wrap(err, "PushSGXData: Error in getting client object")
	}

	conf := config.Global()
	if conf == nil {
		return false, errors.Wrap(errors.New("PushSGXData: Configuration pointer is null"), "Config error")
	}

	pushURL := conf.ScsBaseURL + "/certification/v1/platforms"
	log.Debug("PushSGXData: URL: ", pushURL)
	for i := conf.HostStartId; i < conf.HostStartId+conf.NumberOfHosts; i++ {
		ExtractSGXPlatformValues(i)
		hardwareUUID = "4219f9d3-c8c9-da13-bead-5f0445948a37"
		requestStr := map[string]string{
			"enc_ppid":      pdata.EncryptedPPID,
			"cpu_svn":       pdata.CPUSvn,
			"pce_svn":       pdata.PceSvn,
			"pce_id":        pdata.PceID,
			"qe_id":         pdata.QeID,
			"manifest":      pdata.Manifest,
			"hardware_uuid": hardwareUUID}

		reqBytes, err := json.Marshal(requestStr)

		if err != nil {
			return false, errors.Wrap(err, "PushSGXData: Marshal error:"+err.Error())
		}

		req, err := http.NewRequest("POST", pushURL, bytes.NewBuffer(reqBytes))
		if err != nil {
			return false, errors.Wrap(err, "PushSGXData: Failed to Get New request")
		}

		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+conf.BearerToken)

		tokenExpired, err := utils.JwtHasExpired(conf.BearerToken)
		if err != nil {
			slog.WithError(err).Error("PushSGXData: Error verifying token expiry")
			return false, errors.Wrap(err, "PushSGXData: Error verifying token expiry")
		}
		if tokenExpired {
			slog.Warn("PushSGXData: Token is about to expire within 7 days. Please refresh the token.")
		}

		var retries = 0
		var timeBwCalls = conf.WaitTime

		resp, err := client.Do(req)
		if err != nil || (resp != nil && resp.StatusCode >= http.StatusInternalServerError) {

			for {
				log.Errorf("Retrying for '%d'th time: ", retries)
				req.Body = ioutil.NopCloser(bytes.NewBuffer(reqBytes))
				resp, err = client.Do(req)

				if resp != nil && resp.StatusCode < http.StatusInternalServerError {
					log.Info("PushSGXData: Status code received: " + strconv.Itoa(resp.StatusCode))
					log.Debug("PushSGXData: Retry count now: " + strconv.Itoa(retries))
					break
				}

				if err != nil {
					log.WithError(err).Info("PushSGXData:")
				}

				if resp != nil {
					log.Error("PushSGXData: Invalid status code received: " + strconv.Itoa(resp.StatusCode))
				}

				retries++
				if retries >= conf.RetryCount {
					log.Errorf("PushSGXData: Retried %d times, Sleeping %d minutes...", conf.RetryCount, timeBwCalls)
					time.Sleep(time.Duration(timeBwCalls) * time.Minute)
					retries = 0
				}
			}
		}

		if resp != nil && resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusOK {
			err = resp.Body.Close()
			if err != nil {
				log.WithError(err).Error("Error closing response")
			}
			return false, errors.New("PushSGXData: Invalid status code received: " + strconv.Itoa(resp.StatusCode))
		}

		var pushResponse SCSPushResponse

		dec := json.NewDecoder(resp.Body)
		dec.DisallowUnknownFields()

		err = dec.Decode(&pushResponse)
		if err != nil {
			return false, errors.Wrap(err, "PushSGXData: Read Response failed")
		}

		log.Debug("PushSGXData: Received SCS Response Data: ", pushResponse)
		err = resp.Body.Close()
		if err != nil {
			log.WithError(err).Error("Error closing response")
		}
	}
	return true, nil
}
