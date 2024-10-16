#!/bin/bash -e

cd ~
chmod 755 .config/polybar/launch.sh
chmod 755 .config/polybar/iostat.sh
mkdir -p .cache/yay
cd .cache/yay
git clone https://aur.archlinux.org/yay-bin.git
cd yay-bin
echo "Please enter your user password when you are asked. We may ask a few times."
sleep 5
makepkg -si --noconfirm
yay --noconfirm --answerdiff None --answerclean None --noremovemake --mflags "--noconfirm" -S dracut-ukify waterfox-bin ungoogled-chromium-bin slack-desktop sddm-slice-git nvim-packer-git
echo "Setting up user neovim. Enter ':w' once, wait, then 'q', then ':q'".
sleep 5
nvim ~/.config/nvim/lua/plugins.lua
sed -i '$ d' ~/.bashrc
echo '
if [ $TILIX_ID ] || [ $VTE_VERSION ]; then
        source /etc/profile.d/vte.sh
fi

export GPG_TTY=$(tty)

alias novpn="systemd-run --user --slice=novpn.slice --scope"
alias nsudo="sudo systemd-run --slice=system-novpn.slice --scope"
alias move="rsync -aHAPUXv --remove-source-files"
alias smove="sudo rsync -aHAPUXv --remove-source-files"
' >> ~/.bashrc
rm ~/first_boot.sh
