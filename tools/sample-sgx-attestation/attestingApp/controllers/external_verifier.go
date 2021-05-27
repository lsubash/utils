/*
 * Copyright (C) 2020 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
package controllers

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"github.com/intel-secl/sample-sgx-attestation/v4/common"
	"github.com/pkg/errors"
	cos "intel/isecl/lib/common/v4/os"
	"io/ioutil"
	"net/http"
)

// ExternalVerifier verifies quotes when SGX Attestation service is NOT operating in standalone mode
// in cooperation with CMS, AAS, SQVS etc.
type ExternalVerifier struct {
	Config     *common.Configuration
	CaCertsDir string
}

type QuoteData struct {
	QuoteBlob string `json:"quote"`
	UserData  string `json:"userData"`
}

// VerifyQuote implements the Verifier interface
func (ev ExternalVerifier) VerifyQuote(quote string, key string) (QuoteVerifyAttributes, error) {
	log.Info("Verifying SGX quote with SQVS...")
	url := ev.Config.SqvsUrl + common.VerifyQuote

	var quoteData QuoteData
	quoteData.QuoteBlob = quote

	// UserData in Quote Verification Request : SQVS compares the hash of UserData
	// against the UserData generated inside the enclave. The result of the match
	// is received in UserDataMatch field in SQVS Quote Verification Response.
	// In this example, we use UserData to verify whether the public key
	// received by the attesting App is indeed generated by the enclave.
	//
	// Refer attestedApp/libenclave/Enclave.cpp - enclave_create_report function for
	// UserData generation inside the enclave.
	quoteData.UserData = key

	// Encode quote to JSON
	buffer := new(bytes.Buffer)
	err := json.NewEncoder(buffer).Encode(quoteData)
	if err != nil {
		return QuoteVerifyAttributes{}, errors.Wrap(err, "Error in encoding the quote.")
	}

	// Send request to external SQVS
	req, err := http.NewRequest("POST", url, buffer)
	if err != nil {
		return QuoteVerifyAttributes{}, errors.Wrap(err, "Error in Creating request.")
	}
	req.Header.Add("Accept", "application/json")
	req.Header.Set("Content-Type", "application/json")

	// Get the SystemCertPool, continue with an empty pool on error
	// CMS root CA cert might be available there.
	rootCAs, _ := x509.SystemCertPool()
	if rootCAs == nil {
		rootCAs = x509.NewCertPool()
	}

	// Look for certificates in the current directory
	// CMS root CA cert might be available.
	rootCaCertPems, err := cos.GetDirFileContents("./", "*.pem")

	for _, rootCACert := range rootCaCertPems {
		rootCAs.AppendCertsFromPEM(rootCACert)
		// If we couldn't load CMS root CA from the system pool
		// or the current directory, https call to SQVS would fail with
		// "x509: certificate signed by unknown authority" error.
	}

	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: false,
				RootCAs:            rootCAs,
			},
		},
	}

	log.Infof("Posting quote to %s ...", url)

	resp, err := client.Do(req)
	if resp != nil {
		defer func() {
			derr := resp.Body.Close()
			if derr != nil {
				log.WithError(derr).Error("Error closing quote verification response body.")
			}
		}()
	}

	if err != nil {
		log.Error(err)
		return QuoteVerifyAttributes{}, errors.Wrap(err, "Error in sending quote verification request.")
	}

	if resp.StatusCode != http.StatusOK {
		log.Error("Status Code : ", resp.StatusCode)
		return QuoteVerifyAttributes{}, errors.New("Quote Verification failed.")
	}

	log.Info("SQVS Response Status:", resp.Status)

	response, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		log.WithError(err).Error("Could not read Quote Verification Response body.")
		return QuoteVerifyAttributes{}, err
	}

	log.Info("SQVS Response Body:", string(response))

	// Unmarshal JSON response
	var responseAttributes QuoteVerifyAttributes
	err = json.Unmarshal(response, &responseAttributes)
	if err != nil {
		return QuoteVerifyAttributes{}, errors.Wrap(err, "Error in unmarshalling response.")
	}
	log.Info("Successfully verified quote.")

	return responseAttributes, nil
}
