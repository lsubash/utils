/*
 * Copyright (C) 2020  Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */

package resource

import (
	"bytes"
	"encoding/json"
	"github.com/gorilla/handlers"
	"github.com/gorilla/mux"
	"github.com/pkg/errors"
	"intel/isecl/lib/clients/v3"
	"intel/isecl/sgx_agent/v3/config"
	"intel/isecl/sgx_agent/v3/constants"
	"intel/isecl/sgx_agent/v3/utils"
	"io/ioutil"
	"math/rand"
	"net/http"
	"strconv"
	"time"
)

// MSR.IA32_Feature_Control register tells availability of SGX
const (
	FeatureControlRegister = 0x3A
	MSRDevice              = "/dev/cpu/0/msr"
)

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

type PlatformResponse struct {
	SGXData SGXDiscoveryData `json:"sgx-data"`
	PData   PlatformData     `json:"sgx-platform-data"`
}

var (
	pckIDRetrievalInfo = []string{"PCKIDRetrievalTool", "-f", "/opt/pckData"}
)

type SCSPushResponse struct {
	Status  string `json:"Status"`
	Message string `json:"Message"`
}

var sgxData SGXDiscoveryData
var platformData PlatformData

func ProvidePlatformInfo(router *mux.Router) {
	log.Trace("resource/sgx_detection:ProvidePlatformInfo() Entering")
	defer log.Trace("resource/sgx_detection:ProvidePlatformInfo() Leaving")

	router.Handle("/host/{id}", handlers.ContentTypeHandler(getPlatformInfo(), "application/json")).Methods("GET")
}

func random(min int, max int) int {
	return rand.Intn(max-min) + min
}

func ExtractSGXPlatformValues(id int) (error, *SGXDiscoveryData, *PlatformData) {
	id_str := strconv.Itoa(id)
	var sgx_enablement_info *SGXDiscoveryData
	var sgx_platform_data *PlatformData
	sgxData.SgxSupported = true
	sgxData.SgxEnabled = true
	sgxData.FlcEnabled = true
	sgxData.EpcStartAddress = "0x7020" + id_str
	sgxData.EpcSize = "189.5" + id_str + " MB"
	sgxData.maxEnclaveSizeNot64 = 11
	sgxData.maxEnclaveSize64 = 12
	platformData.EncryptedPPID = strconv.Itoa(random(100000, 999999)) + "85b1ba8330b750b7a52fa03e8137c06ba050561d9d5a3391e16304809761ef9b8d04237ab7cee326a140c697fc60ab8eade69b39ae676e7b4201200b864f8e1737f47b1d20a431f2b2bcdfd4927ac330a897962a95e94597c682a8de74c8b6a99dd633bceb78515f58ed760acab856f55552dc868b77857f8ceeb88cd2f94a1fadd3d484c95203f064341fbc02b914560716873147ce0feb3f9581f9b911fcd60f9abd7d4d8e6f06a145964a6e5032a5e2721cf0d45493618036110ec3ff5b01084097acf2d9783241ac57b6826404f41eea380e55681cbc5fbcfd07368326dad1a67a54a48ba7aa2945b01d673c91edce044db2929b7cd5f21909513ef54ffc98fadcb94e31f358fe2dc95ff6fe3c8473052ec9b99abaf8501c5c1167b580546349e969d99f224ca0189c4e739cee48799b92909a175f59e2de49a741a0863d42780ab524a7420493e2fa35a191e0bd2b37e49d05c512f70bf46d26f25d6e809a007807cd4b00682bedbd5412553677c9e8af746064c233779195af2c"
	platformData.PceID = "0000"
	platformData.CPUSvn = "0202ffffff8002000000010000000000"
	platformData.PceSvn = "0a00"
	for len(id_str) < 6 {
		id_str = "0" + id_str
	}

	platformData.QeID = "bf2b" + id_str + "b1" + "bb879" + "a788a" + "1c104" + "f67ff"
	log.Debug("ExtractSGXPlatformValues: ", platformData.QeID)
	platformData.Manifest = "qwertyqwertyutreqwertyuiqwertyuytrewqwertyuytrewqwertyuytrewqwertyuqwertyuiopppoiuytrewqqwertyuioppoiuytrewqasdfghjmkqazwxsecdrtfvbgyhu"

	sgx_enablement_info = &sgxData
	sgx_platform_data = &platformData
	return nil, sgx_enablement_info, sgx_platform_data
}

func check(e error) {
	if e != nil {
		panic(e)
	}
}

func getPlatformInfo() errorHandlerFunc {
	return func(httpWriter http.ResponseWriter, httpRequest *http.Request) error {
		log.Trace("resource/sgx_detection:GetPlatformInfo() Entering")
		defer log.Trace("resource/sgx_detection:GetPlatformInfo() Leaving")

		err := authorizeEndpoint(httpRequest, constants.HostDataReaderGroupName, true)
		if err != nil {
			return err
		}

		if httpRequest.Header.Get("Accept") != "application/json" {
			return &resourceError{Message: "Accept type not supported", StatusCode: http.StatusNotAcceptable}
		}

		conf := config.Global()
		if conf == nil {
			return errors.Wrap(errors.New("getPlatformInfo: Configuration pointer is null"), "Config error")
		}

		res := PlatformResponse{SGXData: sgxData, PData: platformData}

		httpWriter.Header().Set("Content-Type", "application/json")
		httpWriter.WriteHeader(http.StatusOK)
		js, err := json.Marshal(res)
		if err != nil {
			log.Debug("Marshalling unsuccessful")
			return &resourceError{Message: err.Error(), StatusCode: http.StatusInternalServerError}
		}
		_, err = httpWriter.Write(js)
		if err != nil {
			return &resourceError{Message: err.Error(), StatusCode: http.StatusInternalServerError}
		}
		slog.Info("Platform data retrieved by:", httpRequest.RemoteAddr)
		return nil
	}
}

func PushSGXData(pdata *PlatformData) (bool, error) {
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
		requestStr := map[string]string{
			"enc_ppid": pdata.EncryptedPPID,
			"cpu_svn":  pdata.CPUSvn,
			"pce_svn":  pdata.PceSvn,
			"pce_id":   pdata.PceID,
			"qe_id":    pdata.QeID,
			"manifest": pdata.Manifest}

		reqBytes, err := json.Marshal(requestStr)

		if err != nil {
			return false, errors.Wrap(err, "PushSGXData: Marshal error:"+err.Error())
		}

		req, err := http.NewRequest("POST", pushURL, bytes.NewBuffer(reqBytes))
		if err != nil {
			return false, errors.Wrap(err, "PushSGXData: Failed to Get New request")
		}

		req.Header.Set("Content-Type", "application/json")
		err = utils.AddJWTToken(req)
		if err != nil {
			return false, errors.Wrap(err, "PushSGXData: Failed to add JWT token to the authorization header")
		}

		resp, err := client.Do(req)
		if resp != nil && resp.StatusCode == http.StatusUnauthorized {
			// fetch token and try again
			utils.AasRWLock.Lock()
			err = utils.AasClient.FetchAllTokens()
			if err != nil {
				return false, errors.Wrap(err, "PushSGXData: FetchAllTokens() Could not fetch token")
			}
			utils.AasRWLock.Unlock()
			err = utils.AddJWTToken(req)
			if err != nil {
				return false, errors.Wrap(err, "PushSGXData: Failed to add JWT token to the authorization header")
			}

			req.Body = ioutil.NopCloser(bytes.NewBuffer(reqBytes))
			resp, err = client.Do(req)
		}

		var retries int = 0
		var timeBwCalls int = conf.WaitTime

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
