#!/bin/bash

## Basic Variables
SCRIPT_NAME=`basename $0`
SCRIPT_DIR=$(cd `dirname $0`;pwd);
SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_NAME}"
CALLED_AS=$0
CALLED_AS_FULL="$0 $@"
START_PWD=`pwd`
TOTAL_POSITIONAL_PARAMETERS=$#
FULL_POSITIONAL_PARAMETER_STRING=$@
TOTAL_PARAMETERS=0
TOTAL_OPTIONS=0
TMP_DIR="/tmp/gentoo-install"
R="$TMP_DIR/chroot"
OUT_IMAGE="Gentoo-Installer-$(date "+%Y-%m-%d").iso"

## Configuration
MIN_OPTIONS=0
MAX_OPTIONS=1
MIN_PARAMETERS=0
MAX_PARAMETERS=0

usage(){
    echo "Usage: " "${SCRIPT_NAME} [-o output_file]";
}

echo_exec_info(){
    echo "Script name: ${SCRIPT_NAME}"
    echo "Script directory: ${SCRIPT_DIR}"
    echo "Script path: ${SCRIPT_PATH}"
    echo "Called as: ${CALLED_AS}"
    echo "Called as full: ${CALLED_AS_FULL}"
    echo "Called from: ${START_PWD}"
    echo "Total options: ${TOTAL_OPTIONS}"
    echo "Total parameters: ${TOTAL_PARAMETERS}"
    echo "Total positional parameters: ${TOTAL_POSITIONAL_PARAMETERS}"
    echo "Full options/parameter string: ${FULL_POSITIONAL_PARAMETER_STRING}"
}

parameter_validation(){
    if [ -n "${MIN_OPTIONS}" ] && [ ${TOTAL_OPTIONS} -lt ${MIN_OPTIONS} ];then
        echo "Not enough options"
        usage
        exit 1
    fi

    if [ -n "${MIN_PARAMETERS}" ] && [ ${TOTAL_PARAMETERS} -lt ${MIN_PARAMETERS} ];then
        echo "Not enough parameters"
        usage
        exit 1
    fi

    if [ -n "${MAX_OPTIONS}" ] && [ ${TOTAL_OPTIONS} -gt ${MAX_OPTIONS} ];then
        echo "Too many options"
        usage
        exit 1
    fi

    if [ -n "${MAX_PARAMETERS}" ] && [ ${TOTAL_PARAMETERS} -gt ${MAX_PARAMETERS} ];then
        echo "Too many parameters"
        usage
        exit 1
    fi
}

chroot_exec() {
  local args="${@}"
  sudo chroot "${R}" /bin/bash -c "${args}"
}

echo_status_category() {
  local args="${@}"
  tput setaf 6
  tput smul
  echo -e "= $args"
  tput sgr0
}

echo_status() {
  local args="${@}"
  tput setaf 4
  tput bold
  echo -e "- $args"
  tput sgr0
}


main(){
  if read -r -s -n 1 -t 15 -p "`tput setaf 3` This script will trash the folder '$TMP_DIR' if it exists, wiping any contents. Are you sure? Press any key in the next 15 seconds to continue...`tput sgr0`" key; then
    # Do Nothing
    echo ""
  else
    echo "Aborting."
    exit -1
  fi
  cd `dirname "${0}"`
  
  echo_status_category "Ensuring $TMP_DIR is clean" 
  if [ -d $TMP_DIR ]; then
    echo_status "Removing $TMP_DIR"
    sudo rm -rf $TMP_DIR
  fi
  echo_status "Creating $TMP_DIR"
  mkdir $TMP_DIR
  echo_status "Acquiring sources"
  source config.sh
  
  echo_status_category "Unpacking ${ISO}"
  mkdir -p $TMP_DIR/mount $TMP_DIR/iso $TMP_DIR/sqfs $TMP_DIR/initrd
  
  echo_status "Mounting ${ISO} (Root permissions needed)"
  sudo mount dl/${ISO} $TMP_DIR/mount -o loop
  cp -a $TMP_DIR/mount/* $TMP_DIR/iso/
  sudo umount $TMP_DIR/mount
  
  echo_status "Unsquashing Filesystem (Root permissions needed)"
  sudo unsquashfs -f -d $TMP_DIR/sqfs $TMP_DIR/iso/image.squashfs
  
  echo_status "Extracting Initrd"
  (cd $TMP_DIR/initrd && pv $TMP_DIR/iso/isolinux/gentoo.igz | xz -d | sudo cpio -id)
  
  echo_status_category "Modifying Stage 3 tarball"
  
  echo_status "Extracting base system"
  mkdir ${R}
  xz -d -c "dl/${STAGE}" | pv | sudo tar -xpf - -C ${R}
  
  echo_status "Binding Filesystems for chroot"
  sudo mount -t proc proc "${R}/proc"
  sudo mount --rbind /dev "${R}/dev"
  sudo mount --make-rslave "${R}/dev"
  sudo mount --rbind /sys "${R}/sys"
  sudo mount --make-rslave "${R}/sys"
  
  echo_status "Extracting portage"
  pv "dl/${PORTAGE}" | sudo tar -xjpf -  -C ${R}/usr/
  sudo cp -f files/package.use ${R}/etc/portage/package.use/all
  sudo cp -f files/package.accept_keywords ${R}/etc/portage/package.accept_keywords
  sudo cp -rf files/repos.conf ${R}/etc/portage/
  sudo sed -i 's/bindist/-bindist/g' ${R}/etc/portage/make.conf
  sudo cp -f /etc/resolv.conf ${R}/etc

  echo_status "Grabbing Git"
  chroot_exec "emerge -q dev-vcs/git"
  
  echo_status "Syncing portage"
  chroot_exec "emerge --sync"
  
  echo_status "Downloading packages to be installed"
  chroot_exec emerge -fq ${EMERGE_BASE_PACKAGES} ${EMERGE_EXTRA_PACKAGES}
  
  echo_status "Repacking tarball"
  sudo umount -R "${R}/proc"
  sudo umount -R "${R}/dev"
  sudo umount -R "${R}/sys"
  sudo tar -capf - -C ${R} . -P | pv -s $(sudo du -sb ${R} | awk '{print $1}') | lzma > builder/base_system.tlz
  
  echo_status_category "Modifying installer image"
  
  echo_status "Setting default boot to installer"
  sed -i 's/ontimeout localhost/ontimeout gentoo/g' $TMP_DIR/iso/isolinux/isolinux.cfg
  
  echo_status "Copying in build tools"
  sudo cp -ar builder $TMP_DIR/sqfs/opt/
  
  echo_status "Adding auto-run for install script"
  echo "echo 'if [ \$(tty) == \"/dev/tty1\" ]; then /opt/builder/full_install.sh; fi' >> $TMP_DIR/sqfs/root/.bashrc" | sudo bash
  
  echo_status_category "Repackaging ${ISO}"
  
  echo_status "Squashing Filesystem"
  rm $TMP_DIR/iso/image.squashfs
  sudo mksquashfs $TMP_DIR/sqfs $TMP_DIR/iso/image.squashfs
  
  echo_status "Zipping Initrd"
  rm $TMP_DIR/iso/isolinux/gentoo.igz
  (cd $TMP_DIR/initrd && find . | sudo cpio --quiet --dereference -o -H newc | lzma > $TMP_DIR/iso/isolinux/gentoo.igz)
  
  echo_status "Packaging into an ISO"
  mkisofs -R -b isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table -c isolinux/boot.cat -iso-level 3 -o $OUT_IMAGE $TMP_DIR/iso/
  
  echo_status_category "Cleaning Up"
  #sudo rm -rf $TMP_DIR

}
# Parse options/parameters
while [ "$1" != "" ]; do
    # Options should always come first before parameters
    if [ "${1:0:1}" = "-" ];then
        TOTAL_OPTIONS=$(($TOTAL_OPTIONS + 1))
        case $1 in
            -o | --output-file )    shift
                                    OUT_IMAGE=$1
                                    ;;
            -h | --help )           usage
                                    exit
                                    ;;
            * )                     echo "Invalid option: " ${1}
                                    usage
                                    exit 1
        esac
    # Parameters are always at the end
    else
        TOTAL_PARAMETERS=$#
        # Ignore them alll
        while [ "$1" != "" ]; do
            shift;
        done
        break;
    fi
    shift
done


#echo_exec_info
parameter_validation
main

