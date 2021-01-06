/*
* Copyright (C) 2020 Intel Corporation
* SPDX-License-Identifier: BSD-3-Clause
 */
package tasks

import (
	"bytes"
	"encoding/json"
	"fmt"
	"github.com/pkg/errors"
	"intel/isecl/lib/clients/v3"
	"intel/isecl/lib/common/v3/setup"
	"intel/isecl/sgx_agent/v3/config"
	"intel/isecl/sgx_agent/v3/constants"
	"intel/isecl/sgx_agent/v3/utils"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	//"strings"
	uuid "github.com/google/uuid"
	"strconv"
)

type CreateHost struct {
	Flags         []string
	Config        *config.Configuration
	ConsoleWriter io.Writer
	hostName      string
}

type Host struct {
	HostName         string `json:"host_name"`
	Description      string `json:"description"`
	ConnectionString string `json:"connection_string"`
	HardwareUUID     string `json:"uuid"`
	Flag             bool   `json:"overwrite"`
}

var (
	hardwareUUIDCmd = []string{"dmidecode", "-s", "system-uuid"}
)

//
// Registers (or updates) HVS with information about the currenct compute
// node (providing the connection string, hostname (ip addr) and tls policy).
//
// If the host already exists, create-host will return an error.
//
func (task CreateHost) Run(c setup.Context) error {
	log.Trace("tasks/create_Host:Run() Entering")
	defer log.Trace("tasks/create_Host:Run() Leaving")
	conf := config.Global()
	var err error
	var host_info, host_info1 Host

	if task.Config.SGXAgentMode == constants.RegistrationMode {
		fmt.Fprintln(task.ConsoleWriter, "Skipping CreateHost in Registration Mode...")
		return nil
	}

	task.hostName, err = utils.GetLocalHostname()
	if err != nil {
		return errors.Wrap(err, "tasks/create_host:Run() Error while getting Local hostName address")
	}

	fmt.Fprintln(task.ConsoleWriter, "Current Hostname for agent is: ", task.hostName, ". Do you want to continue with this(Y/N)??")
	var arg, name string
	_, err = fmt.Scanln(&arg)
	if err != nil {
		return errors.Wrap(err, "tasks/create_host:Run() Error while reading user input")
	}
	if arg == "N" {
		fmt.Fprintln(task.ConsoleWriter, "Please enter (hostname/IP address) you want to give")
		_, err = fmt.Scanln(&name)
		if err != nil {
			return errors.Wrap(err, "tasks/create_host:Run() Error while reading user input")
		}
		task.hostName = name
	}
	fmt.Fprintln(task.ConsoleWriter, "sgx_agent will be registered with hostname: ", task.hostName)

	connectionString, err := utils.GetConnectionString(task.Config)
	if err != nil {
		return err
	}
	for i := conf.HostStartId; i < conf.HostStartId + conf.NumberOfHosts; i++ {
		hostCountInString := strconv.Itoa(i)
		host_info.HostName = task.hostName + hostCountInString
		host_info.Description = "demo0" + hostCountInString
		host_info.ConnectionString = connectionString + "/host/" + hostCountInString
		host_info.Flag = true

		hardwareUUID := uuid.New().String()
		host_info.HardwareUUID = hardwareUUID

		///Now connect to SGX-HVS with all this information.
		HVSUrl := task.Config.SGXHVSBaseUrl
		jsonData, err := json.Marshal(host_info)
		if err != nil {
			return errors.Wrap(err, "tasks/create_hosts:Run() Could not marshal data from SGX TA")
		}

		tokenFromEnv, err := c.GetenvSecret("BEARER_TOKEN", "bearer token")
		if tokenFromEnv == "" || err != nil {
			fmt.Fprintln(os.Stderr, "BEARER_TOKEN is not defined in environment")
			return errors.Wrap(err, "tasks/create_hosts:Run() BEARER_TOKEN is not defined in environment file")
		}

		url := fmt.Sprintf("%s/hosts", HVSUrl)
		request, _ := http.NewRequest("POST", url, bytes.NewBuffer(jsonData))
		request.Header.Set("Content-Type", "application/json")
		request.Header.Set("Authorization", "Bearer "+tokenFromEnv)
		client, err := clients.HTTPClientWithCADir(constants.TrustedCAsStoreDir)
		if err != nil {
			log.WithError(err).Error("sgx-hvsclient/sgx-hvsclient_factory:createHttpClient() Error while creating http client")
			return nil
		}

		httpClient := &http.Client{
			Transport: client.Transport,
		}

		response, err := httpClient.Do(request)
		if response != nil {
			defer func() {
				derr := response.Body.Close()
				if derr != nil {
					log.WithError(derr).Error("Error closing response")
				}
			}()
		}
		if err != nil {
			sLog.WithError(err).Error("tasks/create_Host:Run() Error making request")
			return errors.Wrapf(err, "tasks/create_Host:Run() Error making request %s", url)
		}

		if (response.StatusCode != http.StatusOK) && (response.StatusCode != http.StatusCreated) {
			return errors.Errorf("tasks/create_Host: Run() Request made to %s returned status %d", url, response.StatusCode)
		}

		data, err := ioutil.ReadAll(response.Body)
		if err != nil {
			return errors.Wrap(err, "tasks/create_Host: Run() Error reading response")
		}

		log.Debugf("CreateHost returned json: -%v", string(data))

		err = json.Unmarshal(data, &host_info1)
		if err != nil {
			return errors.Wrap(err, "tasks/create_Host: Run() Error while unmarshaling the response")
		}
	}
	return nil
}

// Using the ip address, query HVS to verify if this host is registered
func (task CreateHost) Validate(c setup.Context) error {
	log.Trace("tasks/CreateHost :Validate() Entering")
	defer log.Trace("tasks/CreateHost:Validate() Leaving")
	return nil
}
