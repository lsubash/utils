#!/bin/bash

TERM_DISPLAY_MODE=color
TERM_COLOR_GREEN="\\033[1;32m"
TERM_COLOR_CYAN="\\033[1;36m"
TERM_COLOR_RED="\\033[1;31m"
TERM_COLOR_YELLOW="\\033[1;33m"
TERM_COLOR_NORMAL="\\033[0;39m"

# Environment:
# - TERM_DISPLAY_MODE
# - TERM_DISPLAY_GREEN
# - TERM_DISPLAY_NORMAL
echo_success() {
  if [ "$TERM_DISPLAY_MODE" = "color" ]; then echo -en "${TERM_COLOR_GREEN}"; fi
  echo ${@:-"[  OK  ]"}
  if [ "$TERM_DISPLAY_MODE" = "color" ]; then echo -en "${TERM_COLOR_NORMAL}"; fi
  return 0
}

# Environment:
# - TERM_DISPLAY_MODE
# - TERM_DISPLAY_RED
# - TERM_DISPLAY_NORMAL
echo_failure() {
  if [ "$TERM_DISPLAY_MODE" = "color" ]; then echo -en "${TERM_COLOR_RED}"; fi
  echo ${@:-"[FAILED]"}
  if [ "$TERM_DISPLAY_MODE" = "color" ]; then echo -en "${TERM_COLOR_NORMAL}"; fi
  return 1
}

# Environment:
# - TERM_DISPLAY_MODE
# - TERM_DISPLAY_YELLOW
# - TERM_DISPLAY_NORMAL
echo_warning() {
  if [ "$TERM_DISPLAY_MODE" = "color" ]; then echo -en "${TERM_COLOR_YELLOW}"; fi
  echo ${@:-"[WARNING]"}
  if [ "$TERM_DISPLAY_MODE" = "color" ]; then echo -en "${TERM_COLOR_NORMAL}"; fi
  return 1
}

echo_info() {
  if [ "$TERM_DISPLAY_MODE" = "color" ]; then echo -en "${TERM_COLOR_CYAN}"; fi
  echo ${@:-"[INFO]"}
  if [ "$TERM_DISPLAY_MODE" = "color" ]; then echo -en "${TERM_COLOR_NORMAL}"; fi
  return 1
}

is_uefi_boot() {
  if [ -d /sys/firmware/efi ]; then
    return 0
  else
    return 1
  fi
}

# Check OS
OS=$(cat /etc/os-release | grep ^ID= | cut -d'=' -f2)
temp="${OS%\"}"
temp="${temp#\"}"
OS="$temp"

TBOOT_DEPENDENCY="tboot-1.9.*"
GRUB_FILE=${GRUB_FILE:-"/boot/grub2/grub.cfg"}
echo "Starting trustagent pre-requisites installation from " $USER_PWD

# Install msr-tools
if [ "$OS" == "rhel" ]; then
  yum install -y msr-tools
fi
if [ "$OS" == "ubuntu" ]; then
  apt-get update -y
  apt install -y msr-tools
fi

if [[ $EUID -ne 0 ]]; then
    echo_failure "This script must be run as root"
    exit 1
fi

install_tboot() {
  if [ "$OS" == "rhel" ]; then
    yum install -y tboot-1.9.10
  fi
  if [ "$OS" == "ubuntu" ]; then
    wget http://archive.ubuntu.com/ubuntu/pool/universe/t/tboot/tboot_1.9.7-0ubuntu2_amd64.deb
    dpkg -i tboot_1.9.*-*
  fi

}
# Check for legacy mode and install tboot
if ! is_uefi_boot; then
  SUEFI_ENABLED="false"
  install_tboot
  if [ $? -ne 0 ]; then
    echo_failure "failed to install tboot"
    exit 1
  fi
fi

# if secure efi is not enabled, require tboot has been installed.  Note: This must
# be done manually until RHEL 8.3 (a manual patch is required).
bootctl status 2> /dev/null | grep 'Secure Boot: disabled' > /dev/null
if [ $? -eq 0 ]; then
    SUEFI_ENABLED="false"

    install_tboot
    if [ $? -ne 0 ]; then
      echo_failure "failed to install tboot"
      exit 1
    fi
fi

# if suefi is enabled, tboot should not be installed
# exit with error when such scenario is detected
bootctl status 2> /dev/null | grep 'Secure Boot: enabled' > /dev/null
if [ $? -eq 0 ]; then
  rpm -qa | grep ${TBOOT_DEPENDENCY} >/dev/null
  if [ $? -eq 0 ]; then
    echo_failure "tagent cannot be installed on a system with both tboot and secure-boot enabled"
    exit 1
  fi
fi

# check if a command is already on path
is_command_available() {
  which $* > /dev/null 2>&1
  local result=$?
  if [ $result -eq 0 ]; then return 0; else return 1; fi
}

is_txtstat_installed() {
  is_command_available txt-stat
}

is_measured_launch() {
  local mle=$(txt-stat | grep 'TXT measured launch: TRUE')
  if [ -n "$mle" ]; then
    return 0
  else
    return 1
  fi
}

define_grub_file() {
  if is_uefi_boot; then
    if [ -f "/boot/efi/EFI/redhat/grub.cfg" ]; then
      DEFAULT_GRUB_FILE="/boot/efi/EFI/redhat/grub.cfg"
    fi
  else
    if [ "$OS" == "rhel" ]; then
       if [ -f "/boot/grub2/grub.cfg" ]; then
         DEFAULT_GRUB_FILE="/boot/grub2/grub.cfg"
       fi
    fi
    if [ "$OS" == "ubuntu" ]; then
       if [ -f "/boot/grub/grub.cfg" ]; then
         DEFAULT_GRUB_FILE="/boot/grub/grub.cfg"
       fi
    fi
  fi
  GRUB_FILE=${GRUB_FILE:-$DEFAULT_GRUB_FILE}
}

is_tpm_driver_loaded() {
  define_grub_file

  if [ ! -e /dev/tpm0 ]; then
    local is_tpm_tis_force=$(grep '^GRUB_CMDLINE_LINUX' /etc/default/grub | grep 'tpm_tis.force=1')
    local is_tpm_tis_force_any=$(grep '^GRUB_CMDLINE_LINUX' /etc/default/grub | grep 'tpm_tis.force')
    if [ -n "$is_tpm_tis_force" ]; then
      echo "TPM driver not loaded, tpm_tis.force=1 already in /etc/default/grub"
    elif [ -n "$is_tpm_tis_force_any" ]; then
      echo "TPM driver not loaded, tpm_tis.force present but disabled in /etc/default/grub"
    else
      sed -i -e '/^GRUB_CMDLINE_LINUX/ s/"$/ tpm_tis.force=1"/' /etc/default/grub
      is_tpm_tis_force=$(grep '^GRUB_CMDLINE_LINUX' /etc/default/grub | grep 'tpm_tis.force=1')
      if [ -n "$is_tpm_tis_force" ]; then
        echo "TPM driver not loaded, added tpm_tis.force=1 to /etc/default/grub"
        grub2-mkconfig -o $GRUB_FILE
      else
        echo "TPM driver not loaded, failed to add tpm_tis.force=1 to /etc/default/grub"
      fi
    fi
    return 1
  fi
  return 0
}

is_reboot_required() {
  local should_reboot=no
  if is_txtstat_installed; then
    if ! is_measured_launch; then
      echo_warning "Not in measured launch environment, reboot required"
      should_reboot=yes
    else
      echo "Already in measured launch environment"
    fi
  fi

  if ! is_tpm_driver_loaded; then
    echo_warning "TPM driver is not loaded, reboot required"
    should_reboot=yes
  else
    echo "TPM driver is already loaded"
  fi

  if [ "$should_reboot" == "yes" ]; then
    return 0
  else
    return 1
  fi
}

is_reboot_required
rebootRequired=$?

export LOG_ROTATION_PERIOD=${LOG_ROTATION_PERIOD:-weekly}
export LOG_COMPRESS=${LOG_COMPRESS:-compress}
export LOG_DELAYCOMPRESS=${LOG_DELAYCOMPRESS:-delaycompress}
export LOG_COPYTRUNCATE=${LOG_COPYTRUNCATE:-copytruncate}
export LOG_SIZE=${LOG_SIZE:-100M}
export LOG_OLD=${LOG_OLD:-12}

mkdir -p /etc/logrotate.d

if [ ! -a /etc/logrotate.d/trustagent ]; then
  echo "/var/log/trustagent/*.log {
    missingok
    notifempty
    rotate $LOG_OLD
    maxsize $LOG_SIZE
    nodateext
    $LOG_ROTATION_PERIOD
    $LOG_COMPRESS
    $LOG_DELAYCOMPRESS
    $LOG_COPYTRUNCATE
}" >/etc/logrotate.d/trustagent
fi

echo_success "Installation succeeded"

configure_tboot_grub_menu(){
  define_grub_file
  if [ "$OS" == "rhel" ]; then
    TBOOT_VERSION=$(rpm -qa | grep tboot | cut -d'-' -f2)
    MENUENTRY="tboot ${TBOOT_VERSION}"
    sed -i "s#GRUB_DEFAULT=.*#GRUB_DEFAULT=\'${MENUENTRY}\'#g" /etc/default/grub
    grub2-mkconfig -o $GRUB_FILE
  fi
  if [ "$OS" == "ubuntu" ]; then
    TBOOT_VERSION=$(apt-cache show tboot | grep Version | head -1 |  cut -d ':' -f 2 | cut -d '-' -f 1)
    MENUENTRY="tboot ${TBOOT_VERSION}"
    sed -i "s#GRUB_DEFAULT=.*#GRUB_DEFAULT=\'${MENUENTRY}\'#g" /etc/default/grub
    grub-mkconfig -o $GRUB_FILE
  fi

}

if [[ $rebootRequired -eq 0 ]] && [[ $SUEFI_ENABLED == "false" ]]; then
    configure_tboot_grub_menu
    if [ $? -ne 0 ]; then
      echo_failure "error while configuring grub menu"
    fi

    echo
    echo "Reboot is required."
    echo
fi
