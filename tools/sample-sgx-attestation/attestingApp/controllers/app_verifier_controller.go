/*
 * Copyright (C) 2020 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
package controllers

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"encoding/gob"

	"io"
	"io/ioutil"
	"math/big"
	"net"
	"strings"

	"github.com/intel-secl/sample-sgx-attestation/v3/common"
	"github.com/pkg/errors"
	logger "github.com/sirupsen/logrus"
)

// TODO : Consolidate loggers.
var log = logger.New()

type customFormatter struct {
	logger.TextFormatter
}

func (f *customFormatter) Format(entry *logger.Entry) ([]byte, error) {
	_, e := f.TextFormatter.Format(entry)
	customLog := "AttestingApp(Golang) : " + entry.Message + "\n"
	return []byte(customLog), e
}

type QuoteVerifyAttributes struct {
	Message                string `json:"Message"`
	ReportData             string `json:"reportData"`
	UserDataMatch          string `json:"userDataMatch"`
	EnclaveIssuer          string `json:"EnclaveIssuer"`
	EnclaveIssuerProductID uint16 `json:"EnclaveIssuerProdID"`
	EnclaveMeasurement     string `json:"EnclaveMeasurement"`
	IsvSvn                 string `json:"IsvSvn"`
	TCBLevel               string `json:"TcbLevel"`
}

type AppVerifierController struct {
	Config             *common.Configuration
	ExtVerifier        ExternalVerifier
	SgxQuotePolicyPath string
}

func wrapSWKByPublicKey(swk []byte, key []byte) ([]byte, error) {
	// Public key format from the enclave : <exponent:4><modulus:n>
	exponentLength := 4

	modArr := key[exponentLength:]
	// Endianess : Key Buffer transmitted from Enclave is in LE.
	for i := 0; i < len(modArr)/2; i++ {
		modArr[i], modArr[len(modArr)-i-1] = modArr[len(modArr)-i-1], modArr[i]
	}
	modulus := big.Int{}
	modulus.SetBytes(modArr)

	exponentArr := key[:exponentLength]
	var ex int32
	buf := bytes.NewReader(exponentArr)
	err := binary.Read(buf, binary.LittleEndian, &ex)
	if err != nil {
		log.Info(err)
		return nil, errors.Wrap(err, "Failed to read exponent from key buffer.")
	}

	pubKey := rsa.PublicKey{N: &modulus, E: int(ex)}
	wrappedSWK, err := rsa.EncryptOAEP(sha256.New(), rand.Reader, &pubKey, swk, nil)
	if err != nil {
		return nil, errors.Wrap(err, "Failed to create cipher text")
	}
	return wrappedSWK, nil
}

func (ca AppVerifierController) GenerateSWK() ([]byte, error) {
	//Key for AES 256 bit
	keyBytes := make([]byte, common.SWKSize)
	_, err := rand.Read(keyBytes)
	if err != nil {
		return nil, errors.Wrap(err, "Failed to read the key bytes")
	}
	return keyBytes, nil
}

func (ca AppVerifierController) SharePubkeyWrappedSWK(conn net.Conn, key []byte, swk []byte) error {
	cipherText, err := wrapSWKByPublicKey(swk, key)
	if err != nil {
		log.Info("Cipher Text generation Failed.", err)
		return err
	}

	log.Info("Wrapped SWK Cipher Text Length : ", len(cipherText))

	var msg common.Message
	msg.Type = common.MsgTypePubkeyWrappedSWK
	msg.PubkeyWrappedSWK.WrappedSWK = cipherText

	log.Info("Sending Public key wrapped SWK message...")
	gobEncoder := gob.NewEncoder(conn)
	err = gobEncoder.Encode(msg)
	if err != nil {
		log.Error("Sending Public key wrapped SWK message failed!")
		return err
	}
	return nil
}

func (ca AppVerifierController) ShareSWKWrappedSecret(conn net.Conn, key []byte, secret []byte) error {
	log.Info("Secret : ", string(secret))

	if len(key) != common.SWKSize {
		log.Errorf("Key length has to be %d bytes.", common.SWKSize)
		return errors.New("Invalid key length.")
	}
	cipherBlock, err := aes.NewCipher(key)
	if err != nil {
		log.Error("Error initialising cipher block", err)
		return err
	}

	gcm, err := cipher.NewGCM(cipherBlock)
	if err != nil {
		log.Error("Error creating GCM", err)
		return err
	}

	nonce := make([]byte, gcm.NonceSize())
	_, err = io.ReadFull(rand.Reader, nonce)
	if err != nil {
		log.Error("Error generating nonce for GCM.")
		return err
	}

	wrappedSecret := gcm.Seal(nonce, nonce, secret, nil)

	// Send
	var msg common.Message
	msg.Type = common.MsgTypeSWKWrappedSecret
	msg.SWKWrappedSecret.WrappedSecret = wrappedSecret

	log.Info("Sending SWK Wrapped Secret message ...")
	gobEncoder := gob.NewEncoder(conn)
	err = gobEncoder.Encode(msg)
	if err != nil {
		log.Error("Error sending SWK Wrapped Secret message!")
		return err
	}

	return nil
}

func (ca AppVerifierController) ConnectAndReceiveQuote(conn net.Conn) (bool, *common.Message) {
	var msg common.Message
	msg.Type = common.MsgTypeConnect
	msg.ConnectRequest.Username = common.AppUsername
	msg.ConnectRequest.Password = common.AppPassword

	// Write to socket
	gobEncoder := gob.NewEncoder(conn)
	err := gobEncoder.Encode(msg)
	if err != nil {
		log.Error("Error sending connect message!")
		return false, nil
	}

	// Receive from socket
	respMsg := &common.Message{}
	gobDecoder := gob.NewDecoder(conn)
	err = gobDecoder.Decode(respMsg)
	if err != nil {
		log.Error("Error receiving SGX Quote + Pubkey message!")
		return false, nil
	}

	return true, respMsg
}

func (ca AppVerifierController) VerifySGXQuote(sgxQuote []byte, enclavePublicKey []byte) bool {
	err := ca.verifyQuote(sgxQuote, enclavePublicKey)
	if err != nil {
		log.WithError(err).Errorf("Error while verifying SGX quote")
		return false
	}
	log.Info("Verified SGX quote successfully.")
	return true
}

// verifySgxQuote verifies the quote
func (ca AppVerifierController) verifyQuote(quote []byte, publicKey []byte) error {
	var err error

	// Initialize logger.
	Formatter := new(customFormatter)
	Formatter.DisableTimestamp = true
	log.SetFormatter(Formatter)

	// Convert byte array to string.
	qData := base64.StdEncoding.EncodeToString(quote)
	key := base64.StdEncoding.EncodeToString(publicKey)

	var responseAttributes QuoteVerifyAttributes
	responseAttributes, err = ca.ExtVerifier.VerifyQuote(qData, key)

	if err != nil {
		return errors.Wrap(err, "Error in quote verification!")
	}

	log.Printf("Verifying against quote policy stored at %s", ca.SgxQuotePolicyPath)

	// Load quote policy from path
	qpRaw, err := ioutil.ReadFile(ca.SgxQuotePolicyPath)
	if err != nil {
		return errors.Wrap(err, "Error reading quote policy file!")
	}

	// split by newline
	lines := strings.Split(string(qpRaw), common.EndLine)
	var mreValue, mrSignerValue string
	for _, line := range lines {
		// split by :
		lv := strings.Split(strings.TrimSpace(line), common.PolicyFileDelim)
		if len(lv) != 2 {
			continue
		}
		// switch by field name
		switch lv[0] {
		case common.MREnclaveField:
			mreValue = lv[1]
		case common.MRSignerField:
			mrSignerValue = lv[1]
		}
	}

	log.Infof("Quote policy has values \n\tMREnclaveField = %s \n\tMRSignerField = %s",
		mreValue, mrSignerValue)

	if responseAttributes.EnclaveIssuer != mrSignerValue {
		log.Errorf("Quote policy mismatch in %s", common.MRSignerField)
		err = errors.Errorf("Quote policy mismatch in %s", common.MRSignerField)
		return err
	} else {
		log.Infof("%s matched with Quote Policy", common.MRSignerField)
	}

	if responseAttributes.EnclaveMeasurement != mreValue {
		log.Errorf("Quote policy mismatch in %s", common.MREnclaveField)
		err = errors.Errorf("Quote policy mismatch in %s", common.MREnclaveField)
		return err
	} else {
		log.Infof("%s matched with Quote Policy", common.MREnclaveField)
	}

	if responseAttributes.UserDataMatch != "true" {
		log.Errorf("UserData (public key hash) did not match!")
		err = errors.Errorf("UserData (public key hash) did not match!")
		return err
	} else {
		log.Infof("User Data (public key hash) matched.")
	}

	return nil
}
