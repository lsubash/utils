/*
 * Copyright (C) 2020 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
package main

// #cgo CFLAGS: -I /opt/intel/sgxsdk/include -I /opt/intel/sgxssl/include -I /usr/lib/ -I ./libenclave/safestringlib/include/ -I ./libenclave/Include/
// #cgo LDFLAGS: -L./attestedApp/out/ -L /usr/lib64  -lssl -lcrypto  -L./libenclave/safestringlib/ -lsafestring -luntrusted -L/opt/intel/sgxssl/lib64 -lsgx_usgxssl
// #include "./libenclave/Untrusted/Untrusted.h"
import "C"

import (
	"crypto/tls"
	"encoding/base64"
	"encoding/gob"
	"encoding/json"
	"fmt"
	"github.com/gorilla/handlers"
	"github.com/gorilla/mux"
	"github.com/intel-secl/sample-sgx-attestation/v4/common"
	"github.com/pkg/errors"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"unsafe"
)

type privilegeError struct {
	StatusCode int
	Message    string
}

func (e privilegeError) Error() string {
	return fmt.Sprintf("%d: %s", e.StatusCode, e.Message)
}

type resourceError struct {
	StatusCode int
	Message    string
}

func (e resourceError) Error() string {
	return fmt.Sprintf("%d: %s", e.StatusCode, e.Message)
}

type errorHandlerFunc func(w http.ResponseWriter, r *http.Request) error

func (ehf errorHandlerFunc) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if err := ehf(w, r); err != nil {
		log.WithError(err).Error("HTTP Error")
		switch t := err.(type) {
		case *resourceError:
			http.Error(w, t.Message, t.StatusCode)
		case resourceError:
			http.Error(w, t.Message, t.StatusCode)
		case *privilegeError:
			http.Error(w, t.Message, t.StatusCode)
		case privilegeError:
			http.Error(w, t.Message, t.StatusCode)
		default:
			http.Error(w, err.Error(), http.StatusInternalServerError)
		}
	}
}

func (a *App) getPubkeyFromEnclave() []byte {
	var keyBuffer []byte
	var pubKeySize C.int
	var keyPtr *C.u_int8_t

	keyPtr = C.get_pubkey(&pubKeySize)
	log.Info("getPubkeyFromEnclave : Pub key length : ", pubKeySize)
	if pubKeySize == 0 {
		return nil
	}

	keyBuffer = C.GoBytes(unsafe.Pointer(keyPtr), pubKeySize)

	return keyBuffer
}

func (a *App) getQuoteAndPubkeyFromEnclave(nonce string) ([]byte, []byte) {
	var qBytes []byte
	var kBytes []byte

	// qSize holds the length of the quote byte array returned from enclave
	var qSize C.int
	var keySize C.int

	// qPtr holds the bytes array of the quote returned from enclave
	var qPtr *C.u_int8_t

	nonceCStr := C.CString(nonce)
	if nonceCStr == nil {
		log.Error("Error marshelling nonce.")
		return kBytes, qBytes
	}

	qPtr = C.get_SGX_Quote(&qSize, &keySize, nonceCStr)
	if qPtr == nil {
		log.Error("Unable to retrive quote from enclave.")
		return kBytes, qBytes
	}

	log.Printf("Quote size : %d", qSize)
	qBytes = C.GoBytes(unsafe.Pointer(qPtr), qSize)
	kBytes = C.GoBytes(unsafe.Pointer(qPtr), qSize+keySize)

	return kBytes, qBytes
}

func (a *App) receiveConnectRequest(connection net.Conn) (error, bool, string) {
	authenticated := false

	gobDecoder := gob.NewDecoder(connection)
	requestMsg := new(common.Message)
	err := gobDecoder.Decode(requestMsg)
	if err != nil {
		log.Error("Decoding connect message failed!")
		return err, authenticated, ""
	}

	if requestMsg.Type != common.MsgTypeConnect {
		err = errors.New("Incorrect message type!")
		log.Error("Incorrect message type!")
		return err, authenticated, ""
	}

	if requestMsg.ConnectRequest.Username == common.AppUsername &&
		requestMsg.ConnectRequest.Password == common.AppPassword {
		authenticated = true
	}

	nonce := requestMsg.ConnectRequest.Nonce

	return err, authenticated, nonce
}

func (a *App) sendPubkeySGXQuote(connection net.Conn, nonce string) error {

	// Get the quote from Enclave
	pubKey, sgxQuote := a.getQuoteAndPubkeyFromEnclave(nonce)

	// Get public key from Enclave.
	pubKey = a.getPubkeyFromEnclave()
	if pubKey == nil {
		log.Error("Fetching public key from enclave failed!")
		return errors.New("Fetching public key from enclave failed!")
	}

	if len(pubKey) == 0 || len(sgxQuote) == 0 {
		log.Error("Fetching quote and public key from enclave failed!")
		return errors.New("Fetching quote and public key from enclave failed!")
	}

	// Prepare response with SGX Quote and Enclave
	log.Info("Sending Pubkey and SGX Quote message...")
	gobEncoder := gob.NewEncoder(connection)
	responseMsg := new(common.Message)
	responseMsg.Type = common.MsgTypePubkeyQuote
	responseMsg.PubkeyQuote.Pubkey = pubKey
	responseMsg.PubkeyQuote.Quote = sgxQuote

	// Send quote + public key to attestingApp
	err := gobEncoder.Encode(responseMsg)
	if err != nil {
		log.Error("Encoding Pubkey Quote message failed!")
	}

	return err
}

func (a *App) receivePubkeyWrappedSWK(connection net.Conn) error {
	log.Info("Receiving Pubkey wrapped SWK message...")
	gobWrappedSWKDecoder := gob.NewDecoder(connection)
	wrappedSWKMsg := new(common.Message)
	err := gobWrappedSWKDecoder.Decode(wrappedSWKMsg)
	if err != nil {
		log.Error("Decoding Pubkey wapped SWK message failed!")
		return err
	}

	if wrappedSWKMsg.Type != common.MsgTypePubkeyWrappedSWK {
		err = errors.New("Incorrect message type!")
		log.Error("Incorrect message type!")
		return err
	}

	log.Info("Wrapped SWK Received length : ", len(wrappedSWKMsg.PubkeyWrappedSWK.WrappedSWK))

	pSize := C.ulong(len(wrappedSWKMsg.PubkeyWrappedSWK.WrappedSWK))
	log.Info("Size of Wrapped SWK : ", pSize)

	pStr := C.CBytes(wrappedSWKMsg.PubkeyWrappedSWK.WrappedSWK)
	p := (*C.uint8_t)(unsafe.Pointer(pStr))

	// Unwrap inside the enclave.
	status := C.unwrap_SWK(p, pSize)
	if status != 0 {
		err = errors.New("SWK unwrapping failed!")
	}

	return err
}

func (a *App) receiveSWKWrappedSecret(connection net.Conn) error {
	log.Info("Receiving SWK wrapped Secret message...")

	gobWrappedSecretDecoder := gob.NewDecoder(connection)
	wrappedSecretMsg := new(common.Message)

	err := gobWrappedSecretDecoder.Decode(wrappedSecretMsg)
	if err != nil {
		log.Error("Decoding wrapped secret message failed!")
		return err
	}

	if wrappedSecretMsg.Type != common.MsgTypeSWKWrappedSecret {
		err = errors.New("Incorrect message type!")
		log.Error("Incorrect message type!")
		return err
	}

	if len(wrappedSecretMsg.SWKWrappedSecret.WrappedSecret) == 0 {
		log.Error("Wrapped secret Size can't be zero")
		err = errors.New("Wrapped secret Size can't be zero!")
		return err
	}

	pSecretSize := C.ulong(len(wrappedSecretMsg.SWKWrappedSecret.WrappedSecret))
	pSecret := C.CBytes(wrappedSecretMsg.SWKWrappedSecret.WrappedSecret)
	pSecretPtr := (*C.uint8_t)(unsafe.Pointer(pSecret))

	//Unwrap the secret inside the Enclave
	status := C.unwrap_secret(pSecretPtr, pSecretSize)
	if status != 0 {
		err = errors.New("Unwrapping of secret failed!")
	}

	return err
}

func (a *App) handleConnection(connection net.Conn) error {
	defer connection.Close()

	// Step 1 - Receive a connect request
	err, authenticated, nonce := a.receiveConnectRequest(connection)
	if err != nil {
		log.Error("server:handleConnection : ", err)
		return err
	}

	if !authenticated {
		err = errors.New("Connection authentication failed!")
		log.Error("server:handleConnection : ", err)
		return err
	}

	// Step 2 - Get the quote from enclave and send it to
	// the attesting app.
	err = a.sendPubkeySGXQuote(connection, nonce)
	if err != nil {
		log.Error("server:handleConnection : ", err)
		return err
	}

	// Step 3 - Wait and receive public key wrapped SWK.
	err = a.receivePubkeyWrappedSWK(connection)
	if err != nil {
		log.Error("server:handleConnection : ", err)
		return err
	}

	// Step 4 - Receive SWK wrapped secret
	err = a.receiveSWKWrappedSecret(connection)
	if err != nil {
		log.Error("server:handleConnection : ", err)
		return err
	}

	return nil
}

// EnclaveInit initializes the enclave.
func (a *App) EnclaveInit() error {
	log.Trace("EnclaveInit Entering")
	defer log.Trace("EnclaveInit Leaving")

	var enclaveInitStatus C.int

	// Initialize enclave
	log.Info("Initializing enclave...")
	enclaveInitStatus = C.init()

	if enclaveInitStatus != 0 {
		return errors.Errorf("EnclaveInit Failed to initialize enclave. Error code: %d", enclaveInitStatus)
	}

	log.Info("Enclave initialized.")

	return nil
}

// EnclaveDestroy cleans up the enclave on exit
func (a *App) EnclaveDestroy() error {
	log.Trace("EnclaveDestroy Entering")
	defer log.Trace("EnclaveDestroy Leaving")

	// Destroy enclave
	enclaveDestroyStatus := C.destroy_Enclave()

	if enclaveDestroyStatus != 0 {
		return errors.Errorf("Failed to destroy enclave. Error code: %d", enclaveDestroyStatus)
	}

	log.Info("controller/socket_handler:EnclaveInit Destroyed enclave")

	return nil
}

func authorizeEndpoint(r *http.Request) error {
	// Dummy authorization.
	token := r.Header.Get("Authorization")
	if token != common.DummyBearerToken {
		return resourceError{Message: "Bearer token is invalid.", StatusCode: http.StatusUnauthorized}
	}

	return nil
}

// Step 1 - Receive a connect request. Respond with Quote and Public Key
func httpGetQuotePubkey(a *App) errorHandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		err := authorizeEndpoint(r)
		if err != nil {
			return err
		}

		w.Header().Set("Content-Type", "application/json")

		// Note : Robust input validation is skipped for brevity
		// Retrive Nonce from request
		var idr common.IdentityRequest
		err = json.NewDecoder(r.Body).Decode(&idr)
		if err != nil {
			log.Info(err)
			return resourceError{Message: "Unable to parse request.",
				StatusCode: http.StatusBadRequest}

		}
		// Get the quote from Enclave
		pubKey, sgxQuote := a.getQuoteAndPubkeyFromEnclave(idr.Nonce)

		// Get public key from Enclave.
		pubKey = a.getPubkeyFromEnclave()
		if pubKey == nil {
			log.Error("Fetching public key from enclave failed!")
			w.WriteHeader(http.StatusInternalServerError)
			return &resourceError{
				Message:    "Fetching public key from enclave failed.",
				StatusCode: http.StatusInternalServerError}
		}

		// Encode quote and public key.
		encodedQuote := base64.StdEncoding.EncodeToString(sgxQuote)
		encodedPublicKey := base64.StdEncoding.EncodeToString(pubKey)

		res := common.IdentityResponse{
			Quote:    encodedQuote,
			Userdata: common.UserData{Publickey: encodedPublicKey}}

		js, err := json.Marshal(res)
		if err != nil {
			return &resourceError{
				Message:    err.Error(),
				StatusCode: http.StatusInternalServerError}
		}

		_, err = w.Write(js)
		if err != nil {
			return &resourceError{
				Message:    err.Error(),
				StatusCode: http.StatusInternalServerError}
		}

		return nil
	}
}

// Step 2 : Receive Wrapped SWK from Attesting App
func httpReceiveWrappedSWK(a *App) errorHandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		err := authorizeEndpoint(r)
		if err != nil {
			return err
		}

		w.Header().Set("Content-Type", "application/json")

		// Note : Robust input validation is skipped for brevity

		// Extract wrapped SWK from request
		var ws common.WrappedSWKRequest
		err = json.NewDecoder(r.Body).Decode(&ws)
		if err != nil {
			log.Info(err)
			return resourceError{Message: "Unable to parse request.",
				StatusCode: http.StatusBadRequest}

		}

		swk, err := base64.StdEncoding.DecodeString(ws.SWK)
		if err != nil {
			log.Error("Unable to decode base64 SWK.")
			return resourceError{Message: "Unable to decode base64 SWK.",
				StatusCode: http.StatusBadRequest}
		}

		pSize := C.ulong(len(swk))
		log.Info("Size of Wrapped SWK : ", pSize)

		pStr := C.CBytes(swk)
		p := (*C.uint8_t)(unsafe.Pointer(pStr))

		// Unwrap inside the enclave.
		status := C.unwrap_SWK(p, pSize)
		if status != 0 {
			log.Error("SWK unwrapping failed.")
			return &resourceError{
				Message:    "SWK unwrapping failed!",
				StatusCode: http.StatusInternalServerError}

		}

		return nil
	}
}

// Step 3 : Receive Wrapped Message from Attesting App
func httpReceiveWrappedMessage(a *App) errorHandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) error {
		err := authorizeEndpoint(r)
		if err != nil {
			return err
		}

		w.Header().Set("Content-Type", "application/json")

		// Note : Robust input validation is skipped for brevity

		// Extract wrapped SWK from request
		var wm common.WrappedMessage
		err = json.NewDecoder(r.Body).Decode(&wm)
		if err != nil {
			log.Error(err)
			return resourceError{Message: "Unable to parse request.",
				StatusCode: http.StatusBadRequest}

		}

		wrappedMessage, err := base64.StdEncoding.DecodeString(wm.Message)
		if err != nil {
			log.Error("Unable to decode base64 wrapped message.")
			return resourceError{Message: "Unable to decode base64 wrapped message.",
				StatusCode: http.StatusBadRequest}
		}

		if len(wrappedMessage) == 0 {
			log.Error("Size of wrapped message can't be zero!")
			return &resourceError{
				Message:    "Size of wrapped message can't be zero!",
				StatusCode: http.StatusInternalServerError}
		}

		pSecretSize := C.ulong(len(wrappedMessage))
		pSecret := C.CBytes(wrappedMessage)
		pSecretPtr := (*C.uint8_t)(unsafe.Pointer(pSecret))

		//Unwrap the secret inside the Enclave
		status := C.unwrap_secret(pSecretPtr, pSecretSize)
		if status != 0 {
			return &resourceError{
				Message:    "Unwrapping of secret failed!",
				StatusCode: http.StatusInternalServerError}

		}

		return nil
	}
}

func (a *App) startServer() error {
	log.Trace("app:startServer() Entering")
	defer log.Trace("app:startServer() Leaving")

	c := a.configuration()
	if c == nil {
		return errors.New("Failed to load configuration")
	}

	log.Info("Starting Attested App ...")

	r := mux.NewRouter()
	r.SkipClean(true)

	r.Handle("/id", handlers.ContentTypeHandler(httpGetQuotePubkey(a), "application/json")).Methods("GET")
	r.Handle("/wrapped_swk", handlers.ContentTypeHandler(httpReceiveWrappedSWK(a), "application/json")).Methods("POST")
	r.Handle("/wrapped_message", handlers.ContentTypeHandler(httpReceiveWrappedMessage(a), "application/json")).Methods("POST")

	serverCert, err := tls.LoadX509KeyPair("cert.pem", "key.pem")
	if err != nil {
		log.WithError(err).Error("app:startServer() Unable to load TLS certificates!")
		return err
	}

	h := &http.Server{
		Addr:    fmt.Sprintf(":%d", c.AttestedAppServicePort),
		Handler: r,

		TLSConfig: &tls.Config{
			Certificates: []tls.Certificate{serverCert},
			ServerName:   common.SelfSignedCertSNI,
		},
	}

	err = a.EnclaveInit()
	if err != nil {
		log.WithError(err).Error("app:startServer() Error initializing enclave!")
		return err
	}

	// Setup signal handlers to gracefully handle termination
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP, syscall.SIGQUIT, syscall.SIGKILL)

	// Dispatch web server go routine
	go func() {
		err := h.ListenAndServeTLS("", "")
		if err != nil {
			log.Info(err)
			log.WithError(err).Info("Failed to start HTTP server")
			stop <- syscall.SIGTERM
		}
	}()

	<-stop

	// let's destroy enclave and exit
	err = a.EnclaveDestroy()

	if err != nil {
		log.WithError(err).Info("app:startServer() Error destroying enclave")
	}

	return nil

}
