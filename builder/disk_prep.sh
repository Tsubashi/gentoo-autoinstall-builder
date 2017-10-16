#!/bin/bash

cd `dirname "${0}"`
source builder.cfg

echo "Rewriting disk label (GPT)"
parted -s "$1" mklabel gpt
echo "Creating GRUB Partition"
parted -s "$1" mkpart primary 1M 2M
parted -s "$1" set 1 bios_grub on 
echo "Creating Boot Partition"
parted -s "$1" mkpart primary 2M 1G
echo "Creating Root Partition"
parted -s "$1" mkpart primary 1G 100%
partprobe > /dev/null 2>&1

echo "Installing filesystems"
mkfs.ext4 -FF "${PART}"
mkfs.ext2 -FF "${BOOT_PART}"
