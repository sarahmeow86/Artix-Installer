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
        echo "Updating package database..."; sleep 1
        pacman -Sy --noconfirm --needed zfs-dkms-git zfs-utils-git gptfdisk && echo "20"
        echo "Installing ZFS OpenRC package..."; sleep 1
        pacman -U --noconfirm misc/zfs-openrc-20241023-1-any.pkg.tar.zst && echo "50"
        echo "Loading ZFS kernel module..."; sleep 1
        modprobe zfs && echo "70"
        echo "Enabling ZFS services..."; sleep 1
        rc-update add zfs-zed boot && rc-service zfs-zed start && echo "80"
        zgenhostid -f && echo "100"
    ) | dialog --gauge "Installing ZFS modules..." 10 70 0

    # Check if ZFS was installed successfully
    if ! modinfo zfs &>/dev/null; then
        error "Error installing ZFS!"
    fi

    printf "%s\n" "${bold}Done!"
}
