#!/bin/bash

chroot_exec() {
    local args="${@}"
    chroot "${R}" /bin/bash -c "${args}"
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

echo_error() {
  local args="${@}"
  tput setaf 4
  echo -e "!!! - $args - !!!"
  tput sgr0
}

source builder.cfg

echo 
echo "=== GENTOO AUTO-INSTALL ==="
echo "| Built from git revision |"
echo "|         ${REV}         |"
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
  echo_error "Unable to find any disk to install on. I checked /dev/{v,s,h}da and got nothing. Make sure the disk is connected and operational and try again."
  exit
fi


if read -r -s -n 1 -t 5 -p "`tput setaf 3`I am about to commence a full installation on $DEV. This will destroy it's current contents. If this is not what you want, press any key to cancel. You have 15 seconds...`tput sgr0`" key; then
  echo_error "Aborting."
  exit
fi
cd `dirname "${0}"`

HOSTNAME=$(shuf -n1 adjectives.txt)-$(shuf -n1 first-names.txt)
R="/mnt/gentoo"    # chroot dir
K="/usr/src/linux" # kernel dir

echo ""
echo_status_category "Creating partitions and formatting disk"
echo_status "Rewriting disk label (GPT)"
parted -s "$DEV" mklabel gpt

echo_status "Creating GRUB Partition"
parted -s "$DEV" mkpart primary 1M 2M
parted -s "$DEV" set 1 bios_grub on 

echo_status "Creating Boot Partition"
parted -s "$DEV" mkpart primary 2M 1G

echo_status "Creating Root Partition"
parted -s "$DEV" mkpart primary 1G 100%
partprobe > /dev/null 2>&1

echo_status "Installing filesystems"
mkfs.ext4 -FF "$DEV""3"
mkfs.ext2 -FF "$DEV""2"

echo_status_category "Preparing for chroot"
echo_status "Mounting root filesystem"
mount "$DEV""3" ${R}

echo_status "Extracting base system"
tar -xpf "base_system.tlz" -C ${R}

echo_status "Mounting boot filesystem"
mount "$DEV""2" ${R}/boot

echo_status "Binding Filesystems for chroot"
mount -t proc proc ${R}/proc
mount --rbind /dev ${R}/dev
mount --rbind /sys ${R}/sys

echo_status "Copying in resolv"
cp -f /etc/resolv.conf ${R}/etc

echo_status "Telling make.conf how many cores we have"
echo "MAKEOPTS=\"-j$(nproc)\"" >> ${R}/etc/portage/make.conf

echo_status_category "Running install in chroot"
echo_status "Syncing portage (Just in Case)"
chroot_exec "emerge --sync"

echo_status "Installing packages"
chroot_exec "emerge --jobs=8 --keep-going ${EMERGE_BASE_PACKAGES} ${EMERGE_EXTRA_PACKAGES}"

echo_status_category "Building Kernel"

echo_status "Running config scripts"
chroot_exec "cd ${K}; yes "" | make mrproper;"
chroot_exec "cd ${K}; yes "" | make localyesconfig;"

echo_status "Building Kernel"
chroot_exec "cd ${K}; make -j$(nproc) ${KERNEL_MAKE_OPTS};"

echo_status "Installing Kernel"
chroot_exec "cd ${K}; make modules_install;"
chroot_exec "cd ${K}; make install;"
chroot_exec "cd ${K}; make clean;"


echo_status_category "Setting up Bootloader"
echo_status "Installing GRUB"
chroot_exec "grub-install $DEV"

echo_status "Configuring bootloader"
cp -f grub ${R}/etc/default/grub
chmod 644 ${R}/etc/default/grub
chroot_exec "grub-mkconfig -o /boot/grub/grub.cfg"

echo_status_category "Configuring services"
echo_status "Installing network init scripts"
# create init script for net.eth0
chroot_exec "cd /etc/init.d/; ln -sf net.lo net.eth0"

echo_status "Configuring salt"
cp -f salt-config ${R}/etc/salt/minion

echo_status "Enabling default services"
for service in acpid syslog-ng cronie net.eth0 sshd ntpd qemu-guest-agent salt-minion; do
    chroot_exec "rc-update add ${service} default"
done

echo_status "Touching up system configurations"
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
echo "${HOSTNAME}" > ${R}/etc/hostname

echo "Generating Filesystem Tables"
# generate fstab
FS_UUID=$(blkid "$DEV""3" | cut -d " " -f2)
BOOT_UUID=$(blkid "$DEV""2" | cut -d " " -f2)
cat > ${R}/etc/fstab << EOF
${FS_UUID}      /       ext4        defaults,noatime,user_xattr 0 1
${BOOT_UUID}    /boot   ext2        defaults,noatime,noauto     1 2
EOF

echo_status "Setting Root Password to 'eye<3Gentoo'"
chroot_exec "echo 'root:eye<3Gentoo' | chpasswd"

echo_status "Copying in the last of the files"
# copy in growpart from cloud-utils package
cp -f growpart ${R}/usr/bin/
chmod 755 ${R}/usr/bin/growpart

# TODO: better cleanup
echo_status_category "Executing final cleanup"
chroot_exec "eselect news read &>/dev/null"
chroot_exec "eix-update"
chroot_exec "emaint all -f"
rm -rf ${R}/usr/portage/distfiles/*
rm -rf ${R}/etc/resolv.conf

# Ask User for hostname
if read -r -s -n 1 -t 5 -p "`tput setaf 3`Press any key to set a custom hostname. I'll wait 15 seconds, then generate one myselfif you don't answer.`tput sgr0`" key; then
  read -s -p "New Hostname: " HOSTNAME
  echo "${HOSTNAME}" > ${R}/etc/hostname
fi




echo ""
echo ""
echo "=== All finished! Make sure to check for any egregious errors. Barring those, go ahead and shutdown and remove the CD to get started! ==="
tput bel
