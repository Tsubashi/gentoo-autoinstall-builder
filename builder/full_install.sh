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

echo "Binding Filesystems for chroot"
./mount_binds.sh

echo "Extracting portage"
./extract_portage.sh
chroot_exec "emerge --sync"

cp -f /etc/resolv.conf ${R}/etc

# install standard packages
echo "Installing packages"
chroot_exec "emerge --jobs=8 --keep-going ${EMERGE_BASE_PACKAGES} ${EMERGE_EXTRA_PACKAGES}"

echo "Copying in kernel configs"
# build and install kernel/initrd
mkdir -p ${R}/etc/kernels/
if [ -f kernel-config ];then
    cp -f kernel-config ${R}/etc/kernels/kernel-config-cloud
fi

# copy config in place
cp -f ${R}/etc/kernels/kernel-config-cloud ${R}/usr/src/linux/.config

echo "Building and installing kernel"
if [ "${KERNEL_CONFIGURE}" = "1" ];then
    chroot_exec "cd ${K}; make nconfig;"
fi

chroot_exec "cd ${K}; make olddefconfig; make ${KERNEL_MAKE_OPTS}; make modules_install; make install; make clean;"

# in case any adjustments are made via menuconfig etc
cp -f ${R}/${K}/.config ${R}/etc/kernels/kernel-config-cloud

# keep the original around for safe keeping
cp -f ${R}/etc/kernels/kernel-config-cloud ${R}/etc/kernels/kernel-config-cloud-original

echo "Installing bootloader (GRUB)"

# install grub to the MBR
chroot_exec "grub-install ${DEV}"

# copy /etc/default/grub
cp -f grub ${R}/etc/default/grub
chmod 644 ${R}/etc/default/grub

# generate grub.cfg
chroot_exec "grub-mkconfig -o /boot/grub/grub.cfg"

# enable serial console
sed -i 's/^#s0:/s0:/g' ${R}/etc/inittab
sed -i 's/^#s1:/s1:/g' ${R}/etc/inittab

echo "Configuring services"
# create init script for net.eth0
chroot_exec "cd /etc/init.d/; ln -sf net.lo net.eth0"

# enable default services
for service in acpid syslog-ng cronie net.eth0 sshd cloud-init-local cloud-init cloud-config cloud-final;do
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

# by default read /etc/hostname as set by cloud-init
cp -f hostname ${R}/etc/conf.d/
chmod 644 ${R}/etc/conf.d/hostname

echo "Generating Filesystem Tables"
# generate fstab
FS_UUID=$(blkid "${PART}" | cut -d " " -f2)
cat > ${R}/etc/fstab << EOF
${FS_UUID}      /       ext4        defaults,noatime,user_xattr 0 1
EOF

echo "Copying in the last of the files"
# copy cloud-init config into place
cp -f cloud.cfg ${R}/etc/cloud/
chmod 644 ${R}/etc/cloud/cloud.cfg

# eventually cloud-init will install this file
cp -f hosts.gentoo.tmpl ${R}/etc/cloud/templates/
chmod 644 ${R}/etc/cloud/templates/hosts.gentoo.tmpl

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
