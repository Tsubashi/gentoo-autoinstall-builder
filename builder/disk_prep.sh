#!/bin/bash

cd `dirname "${0}"`
source builder.cfg

parted -s "${DEV}" mklabel gpt
parted -s "${DEV}" mkpart primary 2048s 100%
partprobe > /dev/null 2>&1

mkfs.ext4 -FF "${PART}"
