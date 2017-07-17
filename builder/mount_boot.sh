#!/bin/bash

cd `dirname "${0}"`
source builder.cfg

mount "${BOOT_PART}" /mnt/gentoo/boot
