/*
 * Copyright (C) 2021 Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
package commands

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"encoding/pem"
	"encoding/xml"
	"fmt"
	"io"
	"io/ioutil"
	"math/big"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	asset_tag "github.com/intel-secl/intel-secl/v3/pkg/lib/asset-tag"
	"github.com/intel-secl/intel-secl/v3/pkg/lib/flavor"
	flavorCommon "github.com/intel-secl/intel-secl/v3/pkg/lib/flavor/common"
	flavorModel "github.com/intel-secl/intel-secl/v3/pkg/lib/flavor/model"
	flavorUtil "github.com/intel-secl/intel-secl/v3/pkg/lib/flavor/util"
	hostConnType "github.com/intel-secl/intel-secl/v3/pkg/lib/host-connector/types"
	"github.com/intel-secl/intel-secl/v3/pkg/lib/verifier"

	"github.com/intel-secl/intel-secl/v3/pkg/model/hvs"
	hvsModel "github.com/intel-secl/intel-secl/v3/pkg/model/hvs"
	taModel "github.com/intel-secl/intel-secl/v3/pkg/model/ta"
	"github.com/pkg/errors"

	pInfo "intel/isecl/lib/platform-info/v3/platforminfo"
)

// use these pair of key and cert to sign and verify to make things easier
var fileLoaded bool
var npwacmFound bool
var certBytes []byte
var certX509 *x509.Certificate
var keyRSA *rsa.PrivateKey

var assetTagHashB64 string
var aikCertX509 *x509.Certificate

var signedFlavors []hvs.SignedFlavor

func Attestation(w io.Writer, tpmSec, aikSec string) error {
	var err error
	tpmOwnerSecret = tpmSec
	aikSecret = aikSec
	if err := initTPM(); err != nil {
		return errors.Wrap(err, "failed to init tpm provider")
	}
	// generate key and cert for testing
	if certX509 == nil {
		err = createTestKeyAndCert()
		if err != nil {
			return errors.Wrap(err, "failed to create cert and key for testing")
		}
	}
	// create asset tag cert
	assetTagCert, err := createAssetTag()
	if err != nil {
		return errors.Wrap(err, "failed to create asset tag")
	}
	tempX509AttrCert, err := flavorModel.NewX509AttributeCertificate(assetTagCert)
	if err != nil {
		return errors.Wrap(err, "flavorModel.NewX509AttributeCertificate(assetTagCert) failed")
	}
	hwUUID, err := pInfo.HardwareUUID()
	if err != nil {
		return errors.Wrap(err, "failed to get hw uuid")
	}
	newTagCert := hvsModel.TagCertificate{
		Certificate:  assetTagCert.Raw,
		Subject:      tempX509AttrCert.Subject,
		Issuer:       assetTagCert.Issuer.String(),
		NotBefore:    assetTagCert.NotBefore.UTC(),
		NotAfter:     assetTagCert.NotAfter.UTC(),
		HardwareUUID: uuid.MustParse(hwUUID),
	}
	newTagCert.SetAssetTagDigest()
	assetTagHashB64 = newTagCert.TagCertDigest
	// get host manifest
	manifest, err := getHostManifest()
	if err != nil {
		return errors.Wrap(err, "failed to create host manifest")
	}
	// generate flavor
	if signedFlavors == nil {
		signedFlavors, err = generateFlavor(manifest, assetTagCert)
		if err != nil {
			return errors.Wrap(err, "failed to create platform flavor")
		}
	}
	certPool := x509.NewCertPool()
	certPool.AddCert(certX509)
	certPool.AddCert(aikCertX509)
	certs := verifier.VerifierCertificates{
		PrivacyCACertificates:    certPool,
		AssetTagCACertificates:   certPool,
		FlavorSigningCertificate: certX509,
		FlavorCACertificates:     certPool,
	}
	v, err := verifier.NewVerifier(certs)
	if err != nil {
		return errors.Wrap(err, "failed to create verifier")
	}
	collectiveTrustReport := hvs.TrustReport{}
	for _, flv := range signedFlavors {
		r, err := v.Verify(manifest, &flv, true)
		if err != nil {
			return errors.Wrap(err, "failed to verify host manifest with flavor")
		}
		collectiveTrustReport.AddResults(r.Results)
	}
	npwacmFound = fileExists(CheckNPWACMFile)
	// if npw_acm detected, report can be untrusted but output is still passed
	// as long as pcr 17 18 is the fault
	passed := collectiveTrustReport.IsTrusted()
	if !passed {
		passed = byPassPCR17And18(&collectiveTrustReport)
	}
	//create time stamp
	t := time.Now().UTC()
	ts := fmt.Sprintf("%d.%02d.%02d-%02d.%02d.%02d",
		t.Year(), t.Month(), t.Day(),
		t.Hour(), t.Minute(), t.Second())
	if passed {
		fmt.Fprintln(w, "Attestation at "+ts+": PASSED")
	} else {
		fmt.Fprintln(w, "Attestation at "+ts+": FAILED")
	}
	if !fileLoaded {
		if saveErr := saveAttestationFiles(); saveErr != nil {
			return errors.Wrap(saveErr, "failed to save attestation files")
		}
	}
	return errors.Wrap(saveHostManifestAndReport(ts, manifest, &collectiveTrustReport), "failed to save host manifest")
}

func createTestKeyAndCert() error {
	privkey, err := rsa.GenerateKey(rand.Reader, 1024)
	if err != nil {
		return errors.Wrap(err, "failed to generate rsa key pair")
	}
	now := time.Now()
	template := &x509.Certificate{
		SerialNumber:       big.NewInt(0),
		NotBefore:          now.Add(-5 * time.Minute),
		NotAfter:           now.Add(365 * 24 * time.Hour),
		KeyUsage:           x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		ExtKeyUsage:        []x509.ExtKeyUsage{},
		SignatureAlgorithm: x509.SHA384WithRSA,
		Issuer: pkix.Name{
			CommonName: "HVS CA",
		},
		Subject: pkix.Name{
			CommonName: "HVS Tag Certificate",
		},
	}
	certDer, err := x509.CreateCertificate(rand.Reader, template, template, &privkey.PublicKey, privkey)
	if err != nil {
		return errors.Wrap(err, "failed to create self signed certificate")
	}
	certificate, err := x509.ParseCertificate(certDer)
	if err != nil {
		return errors.Wrap(err, "failed to parse certificate")
	}
	keyRSA = privkey
	certX509 = certificate
	certBytes = certificate.Raw
	return nil
}

// this function creates asset tag certificate
func createAssetTag() (*x509.Certificate, error) {
	tagConfig := asset_tag.TagCertConfig{
		SubjectUUID: "803f6068-06da-e811-906e-00163566263e",
		PrivateKey:  keyRSA,
		TagCACert:   certX509,
		TagAttributes: []asset_tag.TagKvAttribute{{
			Key:   "Country",
			Value: "US",
		}, {
			Key:   "Country",
			Value: "India",
		}},
		ValidityInSeconds: 1000,
	}
	newTag := asset_tag.NewAssetTag()
	tagCertificate, err := newTag.CreateAssetTag(tagConfig)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create tag cert")
	}
	parsedCert, err := x509.ParseCertificate(tagCertificate)
	if err != nil {
		return nil, errors.Wrap(err, "failed to parse tag cert")
	}
	return parsedCert, nil
}

// this function is doing things happens in function:
//     func (ic *IntelConnector) GetHostManifestAcceptNonce(nonce string) (types.HostManifest, error)
// written in file
//     https://gitlab.devtools.intel.com/sst/isecl/intel-secl/-/blob/v3.1/develop/pkg/lib/host-connector/intel_host_connector.go
func getHostManifest() (*hostConnType.HostManifest, error) {
	var hostInfo taModel.HostInfo
	// hostManifest.HostInfo is platform info
	platformInfo, err := pInfo.GetPlatformInfo()
	if err != nil {
		return nil, errors.Wrap(err, "failed to get platform info")
	}
	platformInfoJSON, err := json.Marshal(platformInfo)
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal platform info")
	}
	err = json.Unmarshal(platformInfoJSON, &hostInfo)
	if err != nil {
		return nil, errors.Wrap(err, "failed to unmarshal host info")
	}
	hostManifest := hostConnType.HostManifest{HostInfo: hostInfo}
	pcrBankList := []string{"SHA1", "SHA256"}
	tpmQuoteByte, err := tpm.GetTpmQuote(aikSecret, quoteNonce, pcrBankList, pcrList)
	if err != nil {
		return nil, errors.Wrap(err, "failed to get tpm quote")
	}
	// Nonce is not checked in the verifier, by pass it for this test
	// not recreating verificationNonceInBytes
	err = tpm.CreateAik(tpmOwnerSecret, aikSecret)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create aik")
	}
	aikPublicKeyBytes, err := tpm.GetAikBytes()
	if err != nil {
		return nil, errors.Wrap(err, "failed to get aik public key bytes")
	}
	aikCertificate, err := signAIK(aikPublicKeyBytes)
	if err != nil {
		return nil, errors.Wrap(err, "failed to parse aik certificate from tpm")
	}
	aikCertX509 = aikCertificate
	aikCertificateBase64 := base64.StdEncoding.EncodeToString(aikCertificate.Raw)

	// read event log measurement file
	if _, err = os.Stat(EventLogFile); os.IsNotExist(err) {
		return nil, errors.Wrap(err, "event log: measure log file not exist")
	}
	eventLogBytes, err := ioutil.ReadFile(EventLogFile)
	err = xml.Unmarshal(eventLogBytes, new(interface{}))
	if err != nil {
		return nil, errors.Wrap(err, "measure log xml is not valid")
	}
	// this was needed to avoid an error in HVS parsing...
	// 'Current state not START_ELEMENT, END_ELEMENT or ENTITY_REFERENCE'
	xml := string(eventLogBytes)
	xml = strings.Replace(xml, " ", "", -1)
	xml = strings.Replace(xml, "\t", "", -1)
	xml = strings.Replace(xml, "\n", "", -1)
	eventLogBytes = []byte(xml)

	// hostConnUtil.VerifyQuoteAndGetPCRManifest uses these operations
	// to extract information for validating nonce
	index := 0
	// quoteInfoLen := binary.BigEndian.Uint16(tpmQuoteByte[0:2])
	index += 2
	// quoteInfo := tpmQuoteByte[index : index+int(quoteInfoLen)]
	index += 6
	tpm2bNameSize := binary.BigEndian.Uint16(tpmQuoteByte[index : index+2])
	index += 2 + int(tpm2bNameSize)
	tpm2bDataSize := binary.BigEndian.Uint16(tpmQuoteByte[index : index+2])
	index += 2
	tpm2bData := tpmQuoteByte[index : index+int(tpm2bDataSize)]
	pcrManifest, err := verifyQuoteAndGetPCRManifest(string(eventLogBytes), tpm2bData, tpmQuoteByte, aikCertificate)
	if err != nil {
		return nil, errors.Wrap(err, "failed to get pcr manifest")
	}
	// asset tags
	if assetTagHashB64 == "" {
		return nil, errors.New("asset tag hasn't be created yet")
	}
	// tcbMeasurments
	var tcbMeasurements []string
	fileInfo, err := ioutil.ReadDir(RamfsDir)
	if err != nil {
		return nil, err
	}
	for _, file := range fileInfo {
		if filepath.Ext(file.Name()) == ".xml" {
			xml, err := ioutil.ReadFile(RamfsDir + file.Name())
			if err != nil {
				return nil, errors.Wrap(err, "error reading manifest file "+file.Name())
			}
			tcbMeasurements = append(tcbMeasurements, string(xml))
		}
	}
	hostManifest.PcrManifest = pcrManifest
	hostManifest.AIKCertificate = aikCertificateBase64
	hostManifest.AssetTagDigest = assetTagHashB64
	// binding not used for attedstation
	hostManifest.BindingKeyCertificate = base64.StdEncoding.EncodeToString(certBytes)
	hostManifest.MeasurementXmls = tcbMeasurements
	return &hostManifest, nil
}

// this function creats platforms
func generateFlavor(m *hostConnType.HostManifest, tagCert *x509.Certificate) ([]hvs.SignedFlavor, error) {
	pfp, err := flavor.NewPlatformFlavorProvider(m, tagCert)
	if err != nil {
		return nil, errors.Wrap(err, "failed creating platform flavor provider")
	}
	flv, err := pfp.GetPlatformFlavor()
	if err != nil {
		return nil, errors.Wrap(err, "failed generating platform flavor")
	}
	unsignedFlavors, err := (*flv).GetFlavorPartRaw(flavorCommon.FlavorPartPlatform)
	if err != nil {
		return nil, errors.Wrap(err, "failed getting flavor parts")
	}
	pfu := flavorUtil.PlatformFlavorUtil{}
	signedFlavors, err := pfu.GetSignedFlavorList(unsignedFlavors, keyRSA)
	if err != nil {
		return nil, errors.Wrap(err, "failed signing flavor")
	}
	return signedFlavors, nil
}

func signAIK(aikPublicKeyBytes []byte) (*x509.Certificate, error) {
	n := new(big.Int)
	n.SetBytes(aikPublicKeyBytes)
	aikPubKey := rsa.PublicKey{N: n, E: 65537}

	serialNumberLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serialNumber, err := rand.Int(rand.Reader, serialNumberLimit)
	if err != nil {
		return nil, errors.Wrap(err, "Failed to generate serial number")
	}
	clientCRTTemplate := x509.Certificate{
		Issuer: pkix.Name{
			CommonName: "aik cert",
		},
		SerialNumber: serialNumber,
		Subject: pkix.Name{
			CommonName: "aik cert issuer",
		},
		NotBefore: time.Now(),
		NotAfter:  time.Now().AddDate(1, 0, 0),
	}
	aikName, err := tpm.GetAikName()
	if err != nil {
		return nil, errors.Wrap(err, "failed to get aik name")
	}
	extSubjectAltName := pkix.Extension{}
	// Oid "2.5.29.17" is for SubjectAlternativeName extension
	extSubjectAltName.Id = asn1.ObjectIdentifier{2, 5, 29, 17}
	extSubjectAltName.Critical = false
	extSubjectAltName.Value = aikName
	clientCRTTemplate.Extensions = []pkix.Extension{extSubjectAltName}

	aikCertByte, err := x509.CreateCertificate(rand.Reader, &clientCRTTemplate, certX509, &aikPubKey, keyRSA)
	if err != nil {
		return nil, errors.Wrap(err, "failed to sign and generate Certificate")
	}
	aikCert, err := x509.ParseCertificate(aikCertByte)
	if err != nil {
		return nil, errors.Wrap(err, "failed to parse aik certificate")
	}
	return aikCert, nil
}

func LoadAttestationFiles() error {
	var err error
	var raw []byte
	// load ca cert
	raw, err = ioutil.ReadFile(CACertFile)
	if err != nil {
		return errors.Wrap(err, "failed to load ca certificate file")
	}
	block, _ := pem.Decode(raw)
	certX509, err = x509.ParseCertificate(block.Bytes)
	if err != nil {
		return errors.Wrap(err, "failed to decode and parse ca certificate")
	}
	// load private key
	raw, err = ioutil.ReadFile(CACertKeyFile)
	if err != nil {
		return errors.Wrap(err, "failed to load ca private key file")
	}
	block, _ = pem.Decode(raw)
	keyRSA, err = x509.ParsePKCS1PrivateKey(block.Bytes)
	if err != nil {
		return errors.Wrap(err, "failed to decode and parse ca private key")
	}
	// load flavor
	raw, err = ioutil.ReadFile(SavedFlavorFile)
	if err != nil {
		return errors.Wrap(err, "failed to load flavor file")
	}
	err = json.Unmarshal(raw, &signedFlavors)
	if err != nil {
		return errors.Wrap(err, "failed to unmarshal flavor file")
	}
	fileLoaded = true
	return nil
}

func saveAttestationFiles() error {
	if certX509 == nil ||
		keyRSA == nil ||
		signedFlavors == nil {
		return errors.New("failed to save attestation files, one or more required object missing")
	}
	var err error
	// save ca cert
	certBlock := &pem.Block{
		Type:  "CERTIFICATE",
		Bytes: certX509.Raw,
	}
	certB := pem.EncodeToMemory(certBlock)
	err = ioutil.WriteFile(CACertFile, certB, 0666)
	if err != nil {
		return errors.Wrap(err, "failed to write ca certificate file")
	}
	// save private key
	privateKeyBlock := &pem.Block{
		Type:  "PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(keyRSA),
	}
	privateKeyB := pem.EncodeToMemory(privateKeyBlock)
	err = ioutil.WriteFile(CACertKeyFile, privateKeyB, 0666)
	if err != nil {
		return errors.Wrap(err, "failed to write ca key file")
	}
	// save flavor
	flavorB, err := json.Marshal(signedFlavors)
	if err != nil {
		return errors.Wrap(err, "failed to marshal flavor")
	}
	err = ioutil.WriteFile(SavedFlavorFile, flavorB, 0666)
	if err != nil {
		return errors.Wrap(err, "failed to write flavor file")
	}
	return nil
}

func saveHostManifestAndReport(ts string, m *hostConnType.HostManifest, r *hvs.TrustReport) error {
	manifestFullpath := path.Join(SavedManifestDir, ts)
	mb, err := json.Marshal(m)
	if err != nil {
		return errors.Wrap(err, "failed to marshal host manifest")
	}
	err = ioutil.WriteFile(manifestFullpath, mb, 0666)
	if err != nil {
		return errors.Wrap(err, "failed to write host manifest file")
	}
	reportFullpath := path.Join(SavedReportDir, ts)
	rb, err := json.Marshal(r)
	if err != nil {
		return errors.Wrap(err, "failed to marshal trust report")
	}
	err = ioutil.WriteFile(reportFullpath, rb, 0666)
	if err != nil {
		return errors.Wrap(err, "failed to write trust report file")
	}
	return nil
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return !os.IsNotExist(err)
}

func byPassPCR17And18(r *hvs.TrustReport) bool {
	if !npwacmFound || r == nil {
		return false
	}
	for _, ri := range r.Results {
		if !ri.Trusted {
			if ri.Rule.ExpectedPcr != nil {
				if ri.Rule.ExpectedPcr.Index != 17 &&
					ri.Rule.ExpectedPcr.Index != 18 {
					return false
				}
			} else {
				return false
			}
		}
	}
	return true
}
