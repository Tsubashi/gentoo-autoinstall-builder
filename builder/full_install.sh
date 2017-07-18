#!/bin/bash

echo 

if read -r -s -n 1 -t 5 -p "I am about to commence a full installation. If this is not what you want, press any key to cancel. You have 15 seconds..." key; then
  echo "Aborting."
  exit
fi
cd `dirname "${0}"`
source builder.cfg

chroot_exec() {
    local args="${@}"
    chroot "${R}" /bin/bash -c "${args}"
}

R="/mnt/gentoo"
K="/usr/src/linux"

echo "Creating partitions and formatting disk"
./disk_prep.sh

echo "Mounting root filesystem"
./mount_root.sh

echo "Extracting base system"
./extract_stage.sh

echo "Mounting boot filesystem"
./mount_boot.sh

echo "Binding Filesystems for chroot"
./mount_binds.sh

echo "Extracting portage"
./extract_portage.sh
chroot_exec "emerge --sync"

cp -f /etc/resolv.conf ${R}/etc

echo "Installing packages"
chroot_exec "emerge --jobs=8 --keep-going ${EMERGE_BASE_PACKAGES} ${EMERGE_EXTRA_PACKAGES}"

echo "Copying in kernel configs"
cp -f kernel-config ${R}/usr/src/linux/.config

echo "Building and installing kernel"
chroot_exec "cd ${K}; make olddefconfig; make -j9 ${KERNEL_MAKE_OPTS}; make modules_install; make install; make clean;"

echo "Installing bootloader (GRUB)"
chroot_exec "grub-install ${DEV}"

echo "Configuring bootloader"
cp -f grub ${R}/etc/default/grub
chmod 644 ${R}/etc/default/grub
chroot_exec "grub-mkconfig -o /boot/grub/grub.cfg"

echo "Configuring services"
# create init script for net.eth0
chroot_exec "cd /etc/init.d/; ln -sf net.lo net.eth0"

# enable default services
for service in acpid syslog-ng cronie net.eth0 sshd ntpd; do
    chroot_exec "rc-update add ${service} default"
done

echo "Touching up system configurations"
# ensure eth0 style nic naming
chroot_exec "ln -sf /dev/null /etc/udev/rules.d/70-persistent-net.rules"
chroot_exec "ln -sf /dev/null /etc/udev/rules.d/80-net-setup-link.rules"

# timezone
chroot_exec "echo 'US/Mountain' > /etc/timezone"

# locale
chroot_exec "echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen"
#chroot_exec "echo 'en_US ISO-8859-1' >> /etc/locale.gen"
chroot_exec "locale-gen"
chroot_exec "eselect locale set en_US.utf8"

# sysctl
chroot_exec "echo 'vm.swappiness = 0' >> /etc/sysctl.d/swappiness.conf"

# let ipv6 use normal slaac
chroot_exec "sed -i 's/slaac/#slaac/g' /etc/dhcpcd.conf"

# by default read /etc/hostname 
cp -f hostname ${R}/etc/conf.d/
chmod 644 ${R}/etc/conf.d/hostname

echo "Generating Filesystem Tables"
# generate fstab
FS_UUID=$(blkid "${PART}" | cut -d " " -f2)
BOOT_UUID=$(blkid "${BBOT_PART}" | cut -d " " -f2)
cat > ${R}/etc/fstab << EOF
${FS_UUID}      /       ext4        defaults,noatime,user_xattr 0 1
${BOOT_UUID}    /boot   ext2        defaults,noatime,noauto     1 2
EOF

echo "Setting Root Password to 'eye<3Gentoo'"
chroot_exec "echo 'eye<3Gentoo' | passwd --stdin"

echo "Copying in the last of the files"
# copy in growpart from cloud-utils package
cp -f growpart ${R}/usr/bin/
chmod 755 ${R}/usr/bin/growpart

# TODO: better cleanup
echo "Executing final cleanup"
chroot_exec "eselect news read &>/dev/null"
chroot_exec "eix-update"
chroot_exec "emaint all -f"
rm -rf ${R}/usr/portage/distfiles/*
rm -rf ${R}/etc/resolv.conf

echo "Shutting down"
shutdown -h now
