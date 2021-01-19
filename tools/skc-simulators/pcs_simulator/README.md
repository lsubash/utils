PCS Simulator
=============

Primary objective of PCS simulator is to simulate the PCS Service behavior for providing the SGX collaterals like PCK Certificate, PCK CRL, TCB Info and QE Identity info.
 

Key features
------------

-   PCS Simulator required to Provide dummy PCKCert, PCKCRL, TCBInfo, QEId to SGX caching service.

System Requirements
-------------------

-   Proxy settings if applicable

Software requirements
---------------------

-   Go 1.14.1 or newer

Step By Step Build Instructions
===============================

Install required shell commands
-------------------------------

### Disable Firewall

``` {.shell}
sudo systemctl stop firewalld

```

### Install `go 1.14.1` or newer


``` {.shell}
wget https://dl.google.com/go/go1.14.1.linux-amd64.tar.gz
tar -xzf go1.14.1.linux-amd64.tar.gz
sudo mv go /usr/local
export GOROOT=/usr/local/go
export PATH=$GOPATH/bin:$GOROOT/bin:$PATH
```

Build PCS Simulator
-------------------

-   Git clone the PCS Simulator

``` {.shell}
git clone https://github.com/intel-secl/utils.git && cd utils
git checkout v3.3.1/develop
cd tools/skc-simulators/pcs_simulator
```

-   Replace PCS URL in /etc/scs/config.yml Sample: http://<pcs simulator ip>:8080/sgx/certification/v3
-   restart SCS

``` {.shell}
scs stop
scs start
```

-   Run command to run the PCS simulator
	go run main.go


### Direct dependencies

  Name       Repo URL                            Minimum Version Required
  ---------- ----------------------------- ------------------------------------
  handlers   github.com/gorilla/handlers                  v1.4.0
  mux        github.com/gorilla/mux                       v1.7.3
  

Links
=====

<https://01.org/intel-secl/>

