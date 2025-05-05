#!/usr/bin/env bash
bold=$(tput setaf 2 bold)      # makes text bold and sets color to 2
bolderror=$(tput setaf 3 bold) # makes text bold and sets color to 3
normal=$(tput sgr0)            # resets text settings back to normal


error() {\
    printf "%s\n" "${bolderror}ERROR:${normal}\\n%s\\n" "$1" >&2; exit 1;
}
if ! command -v dialog &> /dev/null; then
    echo "dialog is not installed. Installing it now..."
    pacman -Sy --noconfirm dialog || { echo "Failed to install dialog. Please install it manually."; exit 1; }
fi


installzfs() {
    printf "%s\n" "${bold}# Installing the ZFS modules"

    # Start the progress bar
    (
        echo "10"; sleep 1
        echo "Updating package database..."; sleep 1
        pacman -Sy --noconfirm --needed zfs-dkms-git zfs-utils-git gptfdisk && echo "50"
        echo "Installing ZFS OpenRC package..."; sleep 1
        pacman -U --noconfirm misc/zfs-openrc-20241023-1-any.pkg.tar.zst && echo "70"
        echo "Loading ZFS kernel module..."; sleep 1
        modprobe zfs && echo "80"
        echo "Enabling ZFS services..."; sleep 1
        rc-update add zfs-zed boot && rc-service zfs-zed start && echo "100"
    ) | dialog --gauge "Installing ZFS modules..." 10 70 0

    # Check if ZFS was installed successfully
    if ! modinfo zfs &>/dev/null; then
        error "Error installing ZFS!"
    fi

    printf "%s\n" "${bold}Done!"
}
