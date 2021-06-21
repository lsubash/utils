/*
 * Copyright (C) 2020  Intel Corporation
 * SPDX-License-Identifier: BSD-3-Clause
 */
package main

import (
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"encoding/xml"
	"fmt"
	taModel "github.com/intel-secl/intel-secl/v4/pkg/model/ta"
	"github.com/nats-io/nats.go"
	"github.com/pkg/errors"
	log "github.com/sirupsen/logrus"
	"io/ioutil"
	"strings"
	"time"
)

var (
	defaultTimeout = 10 * time.Second
)

type natsTAClient struct {
	natsServers                  []string
	natsConnection               *nats.EncodedConn
	natsHostID                   string
	natsTaSubCredentialsFilePath string
}

func newNatsTAClient(natsServers []string, natsHostID, natsTaSubCredentialsFilePath string) (*natsTAClient, error) {
	if len(natsServers) == 0 {
		return nil, errors.New("client/nats_client:NewNatsTAClient() At least one nats-server must be provided.")
	}

	if natsHostID == "" {
		return nil, errors.New("client/nats_client:NewNatsTAClient() The nats-host-id was not provided")
	}

	client := natsTAClient{
		natsServers:                  natsServers,
		natsHostID:                   natsHostID,
		natsTaSubCredentialsFilePath: natsTaSubCredentialsFilePath,
	}

	return &client, nil
}

func (client *natsTAClient) newNatsConnection() (*nats.EncodedConn, error) {

	tlsConfig := tls.Config{
		InsecureSkipVerify: true,
	}

	conn, err := nats.Connect(strings.Join(client.natsServers, ","),
		nats.Secure(&tlsConfig),
		nats.UserCredentials(client.natsTaSubCredentialsFilePath),
		nats.ErrorHandler(func(nc *nats.Conn, s *nats.Subscription, err error) {
			if s != nil {
				log.Infof("client/nats_client:newNatsConnection() NATS: Could not process subscription for subject %q: %v", s.Subject, err)
			} else {
				log.Infof("client/nats_client:newNatsConnection() NATS: Unknown error: %v", err)
			}
		}),
		nats.DisconnectErrHandler(func(_ *nats.Conn, err error) {
			log.Infof("client/nats_client:newNatsConnection() NATS: Client disconnected: %v", err)
		}),
		nats.ReconnectHandler(func(_ *nats.Conn) {
			log.Infof("client/nats_client:newNatsConnection() NATS: Client reconnected")
		}),
		nats.ClosedHandler(func(_ *nats.Conn) {
			log.Infof("client/nats_client:newNatsConnection() NATS: Client closed")
		}))

	if err != nil {
		return nil, fmt.Errorf("Failed to create nats connection: %+v", err)
	}

	encodedConn, err := nats.NewEncodedConn(conn, "json")
	if err != nil {
		return nil, fmt.Errorf("client/nats_client:newNatsConnection() Failed to create encoded connection: %+v", err)
	}

	return encodedConn, nil
}

func (client *natsTAClient) getHostInfo() (taModel.HostInfo, error) {
	hostInfo := taModel.HostInfo{}
	conn, err := client.newNatsConnection()
	if err != nil {
		return hostInfo, errors.Wrap(err, "client/nats_client:GetHostInfo() Error establishing connection to nats server")
	}
	defer conn.Close()

	err = conn.Request(taModel.CreateSubject(client.natsHostID, taModel.NatsHostInfoRequest), nil, &hostInfo, defaultTimeout)
	if err != nil {
		return hostInfo, errors.Wrap(err, "client/nats_client:GetHostInfo() Error getting Host Info")
	}
	return hostInfo, nil
}

func (client *natsTAClient) getTPMQuote(nonce string, pcrList []int, pcrBankList []string) (taModel.TpmQuoteResponse, error) {
	quoteResponse := taModel.TpmQuoteResponse{}
	nonceBytes, err := base64.StdEncoding.DecodeString(nonce)
	if err != nil {
		return quoteResponse, errors.Wrap(err, "client/nats_client:GetTPMQuote() Error decoding nonce from base64 to bytes")
	}
	quoteRequest := taModel.TpmQuoteRequest{
		Nonce:    nonceBytes,
		Pcrs:     pcrList,
		PcrBanks: pcrBankList,
	}

	conn, err := client.newNatsConnection()
	if err != nil {
		return quoteResponse, errors.Wrap(err, "client/nats_client:GetTPMQuote() Error establishing connection to nats server")
	}
	defer conn.Close()

	err = conn.Request(taModel.CreateSubject(client.natsHostID, taModel.NatsQuoteRequest), &quoteRequest, &quoteResponse, defaultTimeout)
	if err != nil {
		return quoteResponse, errors.Wrap(err, "client/nats_client:GetTPMQuote() Error getting quote")
	}
	return quoteResponse, nil
}

func getHostData(ac *AppConfig) error {
	client, err := newNatsTAClient(ac.NatsServers, ac.TaHostId, ac.natsTaSubCredentialsPath)
	hostInfo, err := client.getHostInfo()
	if err != nil {
		return errors.Wrapf(err, "Error getting host-info from TA subscribed to with HostId %s", ac.TaHostId)
	}
	taHostInfo, _ := json.Marshal(hostInfo)
	err = ioutil.WriteFile(ac.hostInfoPath, taHostInfo, 0644)
	if err != nil {
		return errors.Wrapf(err, "Error writing host-info to file %s", ac.hostInfoPath)
	}

	nonce := "+c4ZEmco4aj1G5dTXQvjIMGFd44="
	pcrList := []int{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23}
	pcrbanks := []string{"SHA1", "SHA256"}

	quote, err := client.getTPMQuote(nonce, pcrList, pcrbanks)
	if err != nil {
		return errors.Wrapf(err, "Error getting host-info from TA subscribed to with HostId %s", ac.TaHostId)
	}
	tpmQuote, err := xml.Marshal(quote)
	if err != nil {
		return errors.Wrap(err, "Error marshalling tpm-quote")
	}
	err = ioutil.WriteFile(ac.tpmQuotePath, tpmQuote, 0644)
	if err != nil {
		return errors.Wrapf(err, "Error writing tpm-quote to file %s", ac.tpmQuotePath)
	}
	return nil
}
