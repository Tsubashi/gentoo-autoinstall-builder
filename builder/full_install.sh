#!/bin/bash

echo 
echo "=== GENTOO AUTO-INSTALL ==="
echo "| Built from git revision |"
echo "|         $REV         |"
echo "*-------------------------*" 
echo

# Determine where we are installing
if [ -b /dev/vda ]; then
  DEV=/dev/vda
elif [ -b /dev/sda ]; then
  DEV=/dev/sda
elif [ -b /dev/hda ]; then
  DEV=/dev/hda
else
  echo "Unable to find any disk to install on. I checked /dev/{v,s,h}da and got nothing. Make sure the disk is connected and operational and try again."
  exit
fi


if read -r -s -n 1 -t 5 -p "I am about to commence a full installation on $DEV. This will destroy it's current contents. If this is not what you want, press any key to cancel. You have 15 seconds..." key; then
  echo "Aborting."
  exit
fi
cd `dirname "${0}"`

source builder.cfg
HOSTNAME=$(shuf -n1 adjectives.txt)-$(shuf -n1 first-names.txt)

chroot_exec() {
    local args="${@}"
    chroot "${R}" /bin/bash -c "${args}"
}

R="/mnt/gentoo"
K="/usr/src/linux"

echo "Creating partitions and formatting disk"
echo "Rewriting disk label (GPT)"
parted -s "$DEV" mklabel gpt
echo "Creating GRUB Partition"
parted -s "$DEV" mkpart primary 1M 2M
parted -s "$DEV" set 1 bios_grub on 
echo "Creating Boot Partition"
parted -s "$DEV" mkpart primary 2M 1G
echo "Creating Root Partition"
parted -s "$DEV" mkpart primary 1G 100%
partprobe > /dev/null 2>&1

echo "Installing filesystems"
mkfs.ext4 -FF "$DEV""3"
mkfs.ext2 -FF "$DEV""2"

echo "Mounting root filesystem"
mount "$DEV""3" /mnt/gentoo

echo "Extracting base system"
tar -xjpf "${STAGE}" -C /mnt/gentoo

echo "Mounting boot filesystem"
mount "$DEV""2" /mnt/gentoo/boot

echo "Binding Filesystems for chroot"
mount -t proc proc /mnt/gentoo/proc
mount --rbind /dev /mnt/gentoo/dev
mount --rbind /sys /mnt/gentoo/sys

echo "Extracting portage"
tar -xjpf "${PORTAGE}" -C /mnt/gentoo/usr/
cp -f package.use ${R}/etc/portage/package.use/all
cp -f package.accept_keywords ${R}/etc/portage/package.accept_keywords
echo "MAKEOPTS=\"-j$(nproc)\"" >> ${R}/etc/portage/make.conf
sed -i 's/bindist/-bindist/g' ${R}/etc/portage/make.conf
cp -f /etc/resolv.conf ${R}/etc

echo "Syncing portage (Just in Case)"
chroot_exec "emerge --sync"

echo "Installing packages"
chroot_exec "emerge --jobs=8 --keep-going ${EMERGE_BASE_PACKAGES} ${EMERGE_EXTRA_PACKAGES}"

echo "Copying in kernel configs"
cp -f kernel-config ${R}/usr/src/linux/.config

echo "Building and installing kernel"
chroot_exec "cd ${K}; make olddefconfig; make localyesconfig; make -j$(nproc) ${KERNEL_MAKE_OPTS}; make modules_install; make install; make clean;"

echo "Installing bootloader (GRUB)"
chroot_exec "grub-install $DEV"

echo "Configuring bootloader"
cp -f grub ${R}/etc/default/grub
chmod 644 ${R}/etc/default/grub
chroot_exec "grub-mkconfig -o /boot/grub/grub.cfg"

echo "Configuring services"
# create init script for net.eth0
chroot_exec "cd /etc/init.d/; ln -sf net.lo net.eth0"

# set up salt configuration
cp -f salt-config ${R}/etc/salt/minion
echo "id: \"$HOSTNAME\"" >> ${R}/etc/salt/minion

# enable default services
for service in acpid syslog-ng cronie net.eth0 sshd ntpd qemu-guest-agent salt-minion; do
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
echo "$HOSTNAME" > ${R}/etc/hostname

echo "Generating Filesystem Tables"
# generate fstab
FS_UUID=$(blkid "$DEV""3" | cut -d " " -f2)
BOOT_UUID=$(blkid "$DEV""2" | cut -d " " -f2)
cat > ${R}/etc/fstab << EOF
${FS_UUID}      /       ext4        defaults,noatime,user_xattr 0 1
${BOOT_UUID}    /boot   ext2        defaults,noatime,noauto     1 2
EOF

echo "Setting Root Password to 'eye<3Gentoo'"
chroot_exec "echo 'root:eye<3Gentoo' | chpasswd"

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

echo ""
echo ""
echo "=== All finished! Make sure to check for any egregious errors. Barring those, go ahead and shutdown and remove the CD to get started! ==="
