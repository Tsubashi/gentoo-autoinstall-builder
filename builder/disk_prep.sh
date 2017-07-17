#!/bin/bash

cd `dirname "${0}"`
source builder.cfg

parted -s "${DEV}" mklabel gpt
# GRUB Partition
parted -s "${DEV}" mkpart primary 2048s 1M
# Boot Partition
parted -s "${DEV}" mkpart primary 1M 1G
# Root Partition
parted -s "${DEV}" mkpart primary 1G 100%
partprobe > /dev/null 2>&1

mkfs.ext4 -FF "${PART}"
mkfs.ext2 -FF "${BOOT_PART}"
