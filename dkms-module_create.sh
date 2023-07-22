#!/bin/sh

# see https://www.collabora.com/news-and-blog/blog/2021/05/05/quick-hack-patching-kernel-module-using-dkms/

# make the script stop on error
set -e

BIN_ABSPATH="$(dirname "$(readlink -f "${0}")")"

KERNEL_MODULE_NAME="${1}"
DKMS_MODULE_VERSION="${2}"

# check OS prerequisites --------------------------------------------------------------------------

# perform OS-specific preparation steps
if grep -q "^ID_LIKE=debian" /etc/os-release; then
  apt install build-essential dkms dwarves

  if grep -q "^ID=ubuntu" /etc/os-release; then
    # see https://askubuntu.com/questions/1348250/skipping-btf-generation-xxx-due-to-unavailability-of-vmlinux-on-ubuntu-21-04
    cp /sys/kernel/btf/vmlinux "/usr/lib/modules/$(uname -r)/build/"
  fi
else
  echo "Preparation steps not (yet) supported for your Linux distro. You might want to modify the distro-specific commands."
fi

# set up the actual DKMS module -------------------------------------------------------------------

[ ! -e "/usr/src/${KERNEL_MODULE_NAME}-${DKMS_MODULE_VERSION}" ] && mkdir "/usr/src/${KERNEL_MODULE_NAME}-${DKMS_MODULE_VERSION}"

# determine the installed gcc major SOURCE_MAIN_VERSION
GCC_VERSION_DEFAULT=$( gcc --version | perl -ne 'if (m~^gcc\b.+?(1\d)\.\d{,2}\.\d{,2}~) { print $1; }' )
if [ $GCC_VERSION_DEFAULT -lt 12 ]; then
  if ! which gcc-12 >/dev/null; then
    printf '%s %s\n    %s\n' "Your system uses version $GCC_VERSION_DEFAULT of gcc by default, but SOURCE_MAIN_VERSION 12 is required as a minimum." 'You might want to install it with the following command:' 'sudo apt install gcc-12.'
    exit 3
  else
    # explicitly use gcc-12 (if we use a kernel compiled with gcc-12)
    CC_PARAMETER=" CC=$( which gcc-12 )"
  fi
fi

# create the configuration file for the DKMS module
cat << EOF > "/usr/src/${KERNEL_MODULE_NAME}-${DKMS_MODULE_VERSION}/dkms.conf"
PACKAGE_NAME="${KERNEL_MODULE_NAME}"
PACKAGE_VERSION="${DKMS_MODULE_VERSION}"

BUILT_MODULE_NAME[0]="${KERNEL_MODULE_NAME}"
DEST_MODULE_LOCATION[0]="/updates/dkms"

AUTOINSTALL="yes"
MAKE[0]="make${CC_PARAMETER} -C \${kernel_source_dir} M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build"
PRE_BUILD="dkms-patchmodule.sh sound/pci/hda"
EOF

# create the pre-build script within the DKMS module
cp "${BIN_ABSPATH}/kernel-module_patch.sh" "/usr/src/${KERNEL_MODULE_NAME}-${DKMS_MODULE_VERSION}/kernel-module_patch.sh"
cp "${BIN_ABSPATH}/kernel-version_get.sh" "/usr/src/${KERNEL_MODULE_NAME}-${DKMS_MODULE_VERSION}/kernel-version_get.sh"

# make the pre-build script executable
chmod u+x "/usr/src/${KERNEL_MODULE_NAME}-${DKMS_MODULE_VERSION}/dkms-patchmodule.sh"
