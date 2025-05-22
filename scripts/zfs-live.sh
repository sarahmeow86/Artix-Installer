#!/usr/bin/env bash
bold=$(tput setaf 2 bold)      # makes text bold and sets color to 2
bolderror=$(tput setaf 3 bold) # makes text bold and sets color to 3
normal=$(tput sgr0)            # resets text settings back to normal

# Function to install ZFS modules
# This function is called before the ZFS root pool and datasets have been created
installzfs() {
    printf "%s\n" "${bold}# Installing the ZFS modules"

    # Start the progress bar
    (
        echo "10"; sleep 1
        echo "Installing ZFS packages..."; sleep 1
        pacman -Sy
        pacman -U --noconfirm misc/zfs-dkms-git-*.pkg.tar.zst misc/zfs-utils-git-*.pkg.tar.zst && echo "40"
        echo "Installing ZFS OpenRC package..."; sleep 1
        pacman -U --noconfirm misc/zfs-openrc-*.pkg.tar.zst && echo "70"
        echo "Loading ZFS kernel module..."; sleep 1
        modprobe zfs && echo "90"
        zgenhostid -f && echo "100"
    ) | dialog --gauge "Installing ZFS modules..." 10 70 0

    # Check if ZFS was installed successfully
    if ! modinfo zfs &>/dev/null; then
        error "Error installing ZFS!"
    fi

    printf "%s\n" "${bold}Done!"
}
