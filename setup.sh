#!/bin/bash -e

echo "Welcome to ArchLinux. Please wait while we initialize. Remember to set a supervisor password on your UEFI settings."
sed -i "s/\[options\]/\[options\]\nParallelDownloads = 16/" /etc/pacman.conf
reflector --save /etc/pacman.d/mirrorlist --protocol https --latest 16 --sort rate
pacman -Sy dialog sbctl --noconfirm
while read -r line; do
	if [[ $(echo $line | awk '{print $1}') == "Setup" ]]; then
		if [[ $(echo $line | awk '{print $4}') == "Disabled" ]]; then
			dialog --infobox "Secure boot not ready. Reboot to UEFI settings, set secure boot to setup mode, and try again." 0 0
			exit 1
		fi
	fi
done< <(sbctl status)
devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
clear
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
clear
lang=$(dialog --stdout --menu "Select language" 0 0 0 en_US.UTF-8 English ja_JP.UTF-8 Japanese ) || exit 1
clear
keymap=$(dialog --stdout --menu "Select keyboard layout" 0 0 0 us US jp106 JIS) || exit 1
clear
hostname=$(dialog --stdout --inputbox "Enter hostname (name for computer)" 0 0) || exit 1
: ${hostname:?"hostname cannot be empty"}
clear
hostpassready=""
while [[ -z $hostpassready ]]; do
	hostpass=$(dialog --stdout --passwordbox "Enter device password for LUKS unlock and root" 0 0) || exit 1
	clear
	: ${hostpass:?"password cannot be empty"}
	checkhostpass=$(dialog --stdout --passwordbox "Enter device password again." 0 0) || exit 1
	clear
	if [[ "$hostpass" == "$checkhostpass" ]]; then
		hostpassready="ready"
	else
		dialog --infobox "Passwords did not match. Try again." 0 0
		sleep 3
		clear
	fi
done
username=$(dialog --stdout --inputbox "Enter username (name for user account)" 0 0) || exit 1
: ${username:?"username cannot be empty"}
clear
sgdisk -Z $device
sgdisk -n1:0:+500M -t1:ef00 -c1:EFISYSTEM -n2:0:+1000M -t2:ea00 -c2:XBOOTLDR -N3 -t3:8304 -c3:linux $device
sleep 3
partprobe -s $device
sleep 3
mkfs.fat -F32 -n EFISYSTEM /dev/disk/by-partlabel/EFISYSTEM
mkfs.fat -F32 -n XBOOTLDR /dev/disk/by-partlabel/XBOOTLDR
echo $hostpass | cryptsetup luksFormat /dev/disk/by-partlabel/linux --force-password
echo $hostpass | cryptsetup luksOpen /dev/disk/by-partlabel/linux root
mkfs.btrfs -L linux -f /dev/mapper/root
mount /dev/mapper/root /mnt
mkdir /mnt/{boot,efi}
mount /dev/disk/by-partlabel/EFISYSTEM /mnt/efi
mount /dev/disk/by-partlabel/XBOOTLDR /mnt/boot
for subvol in var var/log var/cache var/tmp srv home; do btrfs subvolume create "/mnt/$subvol"; done
pacstrap /mnt base linux-zen linux-hardened linux-firmware intel-ucode btrfs-progs dracut neovim sudo base-devel reflector sbsigntools sbctl networkmanager usb_modeswitch htop rsync lxqt breeze-icons sddm xscreensaver adobe-source-han-sans-jp-fonts adobe-source-han-serif-jp-fonts noto-fonts-cjk systemd-ukify python git libreoffice-fresh libreoffice-fresh-ja nodejs npm openbox tor nm-connection-editor network-manager-applet picom qemu-desktop libvirt edk2-ovmf virt-manager dnsmasq ebtables intel-gpu-tools docker typescript typescript-language-server keepassxc xclip fcitx5-qt fcitx5-gtk fcitx5-mozc fcitx5-configtool breeze breeze5 breeze-gtk fcitx5-breeze polybar sysstat
echo $hostname > /mnt/etc/hostname
echo "KEYMAP=$keymap" > /mnt/etc/vconsole.conf
sed -i -e "/^#$lang/s/^#//" /mnt/etc/locale.gen
sed -i -e "/^# %wheel ALL=(ALL:ALL) ALL/s/^# //" /mnt/etc/sudoers
arch-chroot /mnt locale-gen
arch-chroot /mnt chattr -i /sys/firmware/efi/efivars/*
btrfs subvolume create /mnt/swap
swap_size=$(free --mebi | awk '/Mem:/ {print $2}')
btrfs filesystem mkswapfile --size "$swap_size"m --uuid clear /mnt/swap/swapfile
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/etc/fstab > /mnt/etc/fstab
cat > /mnt/etc/dracut-ukify.conf <<EOF
colorize=auto
ukify_global_args+=(--cmdline "intel_iommu=on i915.enable_gvt=1 kvm.ignore_msrs=1 i915.enable_guc=0 iommu=pt sysrq_always_enabled=244" )
ukify_global_args+=(--secureboot-private-key /usr/share/secureboot/keys/db/db.key --secureboot-certificate /usr/share/secureboot/keys/db/db.pem)
EOF
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/etc-dracut.conf.d/40-options.conf > /mnt/etc/dracut.conf.d/40-options.conf
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/etc-dracut.conf.d/50-secure-boot.conf > /mnt/etc/dracut.conf.d/50-secure-boot.conf
arch-chroot /mnt sbctl create-keys
arch-chroot /mnt sbctl sign -s -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi
arch-chroot /mnt sbctl sign -s -o /usr/lib/fwupd/efi/fwupdx64.efi.signed /usr/lib/fwupd/efi/fwupdx64.efi
arch-chroot /mnt pacman -S --asdeps binutils elfutils --noconfirm
arch-chroot /mnt dracut -f --uefi --regenerate-all
rm /mnt/etc/dracut.conf.d/50-secure-boot.conf
arch-chroot /mnt bootctl install
arch-chroot /mnt sbctl enroll-keys -m
arch-chroot /mnt systemctl enable systemd-homed.service
arch-chroot /mnt systemctl disable systemd-networkd.service
arch-chroot /mnt systemctl enable systemd-resolved.service
arch-chroot /mnt systemctl enable NetworkManager.service
arch-chroot /mnt systemctl enable libvirtd.service
arch-chroot /mnt systemctl enable docker.service
mkdir -p /mnt/etc/NetworkManager
cat >> /mnt/etc/NetworkManager/NetworkManager.conf <<EOF
[main]
dns=systemd-resolved
[keyfile]
unmanaged-devices=type:wireguard
EOF
mkdir -p /mnt/etc/NetworkManager/dispatcher.d
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/etc-NetworkManager-dispatcher.d/10-secure-net.sh > /mnt/etc/NetworkManager/dispatcher.d/10-secure-net.sh
sed -i "s/user=/user=$username/" /mnt/etc/NetworkManager/dispatcher.d/10-secure-net.sh
arch-chroot /mnt chmod +x /etc/NetworkManager/dispatcher.d/10-secure-net.sh
arch-chroot /mnt systemctl enable NetworkManager-dispatcher.service
mkdir -p /mnt/etc/systemd/system
cat > /mnt/etc/systemd/system/system-novpn.slice <<EOF
[Unit]
Description=novpn.slice for system level
Before=slices.target

[Slice]
EOF
arch-chroot /mnt systemctl daemon-reload
mkdir -p /mnt/etc/libvirt/hooks/
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/qemu > /mnt/etc/libvirt/hooks/qemu
arch-chroot /mnt chmod +x /etc/libvirt/hooks/qemu
mkdir -p /mnt/etc/libvirt/qemu/
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/win10.xml > /mnt/etc/libvirt/qemu/win10.xml
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/win10-test.xml > /mnt/etc/libvirt/qemu/win10-test.xml
if [[ $lang == "ja_JP.UTF-8" ]]; then
  sed -i 's/English/Japanese/' /mnt/etc/libvirt/qemu/win10.xml
  sed -i 's/English/Japanese/' /mnt/etc/libvirt/qemu/win10-test.xml
fi
arch-chroot /mnt virsh define /etc/libvirt/qemu/win10.xml
arch-chroot /mnt virsh define /etc/libvirt/qemu/win10-test.xml
for i in "${!devicelist[@]}"; do
  if [[ $(echo ${devicelist[$i]} | awk '{print $1}') == $device ]]; then
    devicesize=$(echo ${devicelist[$i]} | awk '{print $2}' | sed 's/\..*//')
  fi
done
if [[ $devicesize -ge 1024 ]]; then
  vm_size="256G"
elif [[ $devicesize -ge 512 ]]; then
  vm_size="128G"
else
  vm_size="40G"
fi
arch-chroot /mnt qemu-img create -f qcow2 /var/lib/libvirt/images/win10.qcow2 $vm_size
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/xhost.desktop > /mnt/root/xhost.desktop
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/polybar.desktop > /mnt/root/polybar.desktop
mkdir -p /mnt/root/polybar
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/polybar/config.ini > /mnt/root/polybar/config.ini
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/polybar/iostat.sh > /mnt/root/polybar/iostat.sh
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/polybar/launch.sh > /mnt/root/polybar/launch.sh
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/qemu > /mnt/etc/libvirt/hooks/qemu
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/first_boot.sh > /mnt/root/first_boot.sh
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/home-user-.config-openbox/rc.xml > /mnt/root/openbox-rc.xml
mkdir -p /mnt/root/.config/nvim/lua/config
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/nvim/init.lua > /mnt/root/.config/nvim/init.lua
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/nvim/coc-settings.json > /mnt/root/.config/nvim/coc-settings.json
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/nvim/lua/options.lua > /mnt/root/.config/nvim/lua/options.lua
curl -sL https://raw.githubusercontent.com/akiba-geek/archlinux/develop/nvim/lua/plugins.lua > /mnt/root/.config/nvim/lua/plugins.lua
arch-chroot /mnt chattr +C /home/
sed -i "s/\[options\]/\[options\]\nParallelDownloads = 16/" /mnt/etc/pacman.conf
cat >> /mnt/etc/environment <<EOF
EDITOR=nvim
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF
cat > /mnt/root/setup.sh <<EOF
#!/bin/bash -e

echo "Creating user account."
homectl create $username --storage=luks --fs-type=btrfs --luks-discard=true --auto-resize-mode=shrink-and-grow --rebalance-weight=10 --member-of=wheel,adm,uucp,libvirt,kvm,tor --uid=1000
echo "Starting setup on user account."
homectl activate $username
mkdir -p /home/$username/.config/systemd/user
echo "[Slice]" > /home/$username/.config/systemd/user/novpn.slice
systemctl --user daemon-reload
mkdir -p /home/$username/.config/openbox/
mv /root/openbox-rc.xml /home/$username/.config/openbox/rc.xml
cp -r /root/.config/nvim /home/$username/.config
mv /root/polybar /home/$username/.config/polybar
mkdir -p /home/$username/.config/autostart/
mv /root/xhost.desktop /home/$username/.config/autostart
mv /root/polybar.desktop /home/$username/.config/autostart
mv /root/first_boot.sh /home/$username/first_boot.sh
chmod 755 /home/$username/first_boot.sh
echo "exec /home/$username/first_boot.sh" >> /home/$username/.bashrc
cp /etc/xdg/picom.conf /home/$username/.config
sed -i 's/fade-in-step = 0.03;/fade-in-step = 0.1;/' /home/$username/.config/picom.conf
sed -i 's/fade-out-step = 0.03;/fade-out-step = 0.1;/' /home/$username/.config/picom.conf
chown -R $username:$username /home/$username
echo "Select, and activate a network."
nmtui
clear
reflector --save /etc/pacman.d/mirrorlist --protocol https --latest 16 --sort rate
echo "Finalizing setup on user account."
su $username
homectl deactivate $username
echo "Setting up root neovim. Enter ':w' once, wait, then 'q', then ':q'".
nvim /root/.config/nvim/lua/plugins.lua
swapon /swap/swapfile
rm /root/setup.sh
sed -i '$ d' /etc/profile
cp /usr/lib/sddm/sddm.conf.d/default.conf /etc/sddm.conf
sed -i 's/Current=/Current=slice/' /etc/sddm.conf
systemctl enable --now sddm.service
EOF
arch-chroot /mnt chmod 755 /root/setup.sh
echo "exec /root/setup.sh" >> /mnt/etc/profile
echo "root:$hostpass" | chpasswd --root /mnt
dialog --infobox "Rebooting. Eject USB. Enable Secure Boot in UEFI Settings. Login as root, and setup user account." 0 0
sleep 5
reboot
