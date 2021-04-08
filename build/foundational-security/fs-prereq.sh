declare -a PRE_REQ_PACKAGES
PRE_REQ_PACKAGES=(
https://download-ib01.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/m/makeself-2.4.2-1.el8.noarch.rpm
http://mirror.centos.org/centos/8/PowerTools/x86_64/os/Packages/tpm2-abrmd-devel-2.1.1-3.el8.x86_64.rpm 
http://mirror.centos.org/centos/8/PowerTools/x86_64/os/Packages/trousers-devel-0.3.14-4.el8.x86_64.rpm
https://www.cabextract.org.uk/cabextract-1.9.1-1.i386.rpm
wget 
gcc 
gcc-c++  
git 
patch 
zip 
unzip 
make 
tpm2-tss-2.0.0-4.el8.x86_64 
tpm2-abrmd-2.1.1-3.el8.x86_64 
openssl-devel
)

#install pre-reqs
install_prereqs() {
  local error_code=0
  for package in ${!PRE_REQ_PACKAGES[@]}; do
    local package_name=${PRE_REQ_PACKAGES[${package}]}
    dnf install -y ${package_name}
    local return_code=$?
    if [ ${return_code} -ne 0 ]; then
      echo "ERROR: could not install [${package_name}]"
      return ${return_code}
    fi
  done
   
  return ${error_code}
}


# functions handling i/o on command line
print_help() {
        echo "Usage: $0 [-hs]"
    echo "    -h    print help and exit"
    echo "    -s    pre-req setup for Foundational Security"
}

dispatch_works() {
    mkdir -p ~/.tmp
    if [[ $1 = *"s"* ]] ; then
        install_prereqs
    fi
}

if [ $# -eq 0 ] ; then
    print_help
    exit 1
fi

OPTIND=1
work_list=""
while getopts his opt; do
    case ${opt} in
    h)  print_help; exit 0 ;;
    s)  work_list+="s" ;;
    *)  print_help; exit 1 ;;
    esac
done

# run commands
dispatch_works $work_list
