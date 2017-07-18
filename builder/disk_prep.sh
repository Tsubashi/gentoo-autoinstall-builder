#!/bin/bash

cd `dirname "${0}"`
source builder.cfg

echo "Rewriting disk label (GPT)"
parted -s "${DEV}" mklabel gpt
echo "Creating GRUB Partition"
parted -s "${DEV}" mkpart primary 1M 2M
parted -s "${DEV}" set 1 bios_grub on 
echo "Creating Boot Partition"
parted -s "${DEV}" mkpart primary 2M 1G
echo "Creating Root Partition"
parted -s "${DEV}" mkpart primary 1G 100%
partprobe > /dev/null 2>&1

echo "Installing filesystems"
mkfs.ext4 -FF "${PART}"
mkfs.ext2 -FF "${BOOT_PART}"
