/*
 * Copyright (C) 2020 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
package common

const (
	AppUsername            = "foobar"
	AppPassword            = "21345h8askjdf"
	DummyBearerToken       = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkR1bW15QmVhcmVyVG9rZW4iLCJpYXQiOjE1MTYyMzkwMjJ9.Czed89Gn-nhHGAH2DzVqo453k04eF0PvBuZvvOJeE1Q"
	DefaultAttestedAppHost = "127.0.0.1"
	DefaultAttestedAppPort = 9999
	ProtocolTcp            = "tcp4"
)

const (
	ConfigDir             = "./"
	CaCertsDir            = "./"
	DefaultConfigFilePath = ConfigDir + "config.yml"
	ConfigFile            = "config"
	SgxQuotePolicyPath    = ConfigDir + "sgx-quote-policy.txt"
	EndLine               = "\n"
	VerifyQuote           = "/sgx_qv_verify_quote"
	GetIdentity           = "/id"
	PostWrappedSWK        = "/wrapped_swk"
	PostWrappedMessage    = "/wrapped_message"
	SelfSignedCertSNI     = "attested.app"
	// SWK Size in bytes
	SWKSize = 32
	// NonceSize in bits
	NonceSize = 128
)

// SGX Policy
const (
	MREnclaveField  = "MREnclave"
	MRSignerField   = "MRSigner"
	CpuSvnField     = "CPU_SVN"
	PolicyFileDelim = ":"
)

// Message definitions

type UserData struct {
	Publickey string `json:"public-key"`
}

type IdentityResponse struct {
	Quote    string   `json:"quote"`
	Userdata UserData `json:"user-data"`
}

type IdentityRequest struct {
	Nonce string `json:"nonce"`
}

type WrappedSWKRequest struct {
	SWK string `json:swk`
}

type WrappedMessage struct {
	Message string `json:message`
}

const (
	MsgTypeConnect          uint8 = 1
	MsgTypePubkeyQuote      uint8 = 2
	MsgTypePubkeyWrappedSWK uint8 = 3
	MsgTypeSWKWrappedSecret uint8 = 4
)

type PayloadConnect struct {
	Username string
	Password string
	Nonce    string
}

type PayloadPubkeyQuote struct {
	Pubkey []byte
	Quote  []byte
}

type PayloadPubkeyWrappedSWK struct {
	WrappedSWK []byte
}

type PayloadSWKWrappedSecret struct {
	WrappedSecret []byte
}

type Message struct {
	Type             uint8
	ResponseCode     int
	ConnectRequest   PayloadConnect
	PubkeyQuote      PayloadPubkeyQuote
	PubkeyWrappedSWK PayloadPubkeyWrappedSWK
	SWKWrappedSecret PayloadSWKWrappedSecret
}
