declare -a PRE_REQ_REPO
PRE_REQ_REPO=(
https://download.docker.com/linux/centos/docker-ce.repo
)

declare -a PRE_REQ_PACKAGES
PRE_REQ_PACKAGES=(
https://download-ib01.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/m/makeself-2.4.2-1.el8.noarch.rpm
http://mirror.centos.org/centos/8/PowerTools/x86_64/os/Packages/tpm2-abrmd-devel-2.1.1-3.el8.x86_64.rpm 
http://mirror.centos.org/centos/8/PowerTools/x86_64/os/Packages/trousers-devel-0.3.14-4.el8.x86_64.rpm
https://www.cabextract.org.uk/cabextract-1.9.1-1.i386.rpm
glib2-devel 
glibc-devel 
wget 
gcc 
gcc-c++  
git 
patch 
zip 
unzip 
make 
tpm2-tss-2.0.0-4.el8.x86_64 
openssl-devel
cabextract
)

declare -a PRE_REQ_PACKAGES_DOCKER
PRE_REQ_PACKAGES_DOCKER=(
containers-common
docker-ce-19.03.13
docker-ce-cli-19.03.13
containerd
skopeo
)

declare -a PRE_REQ_PACKAGES_CRIO
PRE_REQ_PACKAGES_CRIO=(
conmon
)


install_prereq_repos() {
  local error_code=0
  for url in ${!PRE_REQ_REPO[@]}; do
    local repo_url=${PRE_REQ_REPO[${url}]}
    dnf config-manager --add-repo=${repo_url}
    local return_code=$?
    if [ ${return_code} -ne 0 ]; then
      echo "ERROR: could not configure [${repo_url}]"
      return ${return_code}
    fi
  done
  return ${error_code}
}

#install generic pre-reqs
install_prereqs_packages() {
  local error_code=0
  for package in ${!PRE_REQ_PACKAGES[@]}; do
    local package_name=${PRE_REQ_PACKAGES[${package}]}
    dnf install -y ${package_name}
    local install_error_code=$?
    if [ ${install_error_code} -ne 0 ]; then
      echo "ERROR: could not install [${package_name}]"
      return ${install_error_code}
    fi
  done
  return ${error_code}
}

#install docker pre-reqs
install_prereqs_packages_docker() {
  local error_code=0
  for package in ${!PRE_REQ_PACKAGES_DOCKER[@]}; do
    local package_name=${PRE_REQ_PACKAGES_DOCKER[${package}]}
    dnf install -y ${package_name}
    local install_error_code=$?
    if [ ${install_error_code} -ne 0 ]; then
      echo "ERROR: could not install [${package_name}]"
      return ${install_error_code}
    fi
  done
  return ${error_code}
}

#install crio pre-reqs
install_prereqs_packages_crio() {
  local error_code=0
  for package in ${!PRE_REQ_PACKAGES_CRIO[@]}; do
    local package_name=${PRE_REQ_PACKAGES_CRIO[${package}]}
    dnf install -y ${package_name}
    local install_error_code=$?
    if [ ${install_error_code} -ne 0 ]; then
      echo "ERROR: could not install [${package_name}]"
      return ${install_error_code}
    fi
  done
  return ${error_code}
}

install_libkmip() {
  local error_code=0
  rm -rf libkmip/
  git clone https://github.com/openkmip/libkmip.git
  cd libkmip
  make uninstall
  make
  local make_error_code=$?
  if [ ${make_error_code} -ne 0 ]; then
    echo "ERROR: Could not make libkmip"
    return ${make_error_code}
  fi
  make install
  local install_error_code=$?
  if [ ${install_error_code} -ne 0 ]; then
    echo "ERROR: Could not make install libkmip"
    return ${install_error_code}
  fi
  return ${error_code}
}


# functions handling i/o on command line
print_help() {
    echo "Usage: $0 [-hdcv]"
    echo "    -h     print help and exit"
    echo "    -d     pre-req setup for Workload Security:Launch Time Protection - Containers with Docker Runtime"
    echo "    -c     pre-req setup for Workload Security:Launch Time Protection - Containers with CRIO Runtime"
    echo "    -v     pre-req setup for Workload Security:Launch Time Protection - VM Confidentiality"
}

dispatch_works() {
    mkdir -p ~/.tmp
    if [[ $1 == *"d"* ]]; then
      echo "Installing Packages for Workload Security:Launch Time Protection - Containers with Docker Runtime..."
      install_prereqs_packages
      install_prereq_repos
      install_prereqs_packages_docker
      install_libkmip
    elif [[ $1 == *"c"* ]]; then
      echo "Installing Packages for Workload Security:Launch Time Protection - Containers with CRIO Runtime..."
      install_prereqs_packages
      install_prereq_repos
      install_prereqs_packages_docker
      install_prereqs_packages_crio
      install_libkmip
    elif [[ $1 == *"v"* ]]; then
      echo "Installing Packages for Workload Security:Launch Time Protection - VM Confidentiality..."
      install_prereqs_packages
      install_libkmip
    else 
      print_help
      exit 1
    fi
}

optstring=":hdcv"
work_list=""
while getopts ${optstring} opt; do
    case ${opt} in
      h) print_help; exit 0 ;;
      d) work_list+="d" ;;
      c) work_list+="c" ;;
      v) work_list+="v" ;;
      *) print_help; exit 1 ;;
    esac
done

# run commands
dispatch_works $work_list
