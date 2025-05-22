#!/usr/bin/env bash
installpkgs() {
    debug $DEBUG_INFO "Starting package installation"
    printf "%s\n" "${bold}Installing packages"

    # Start the progress bar
    (
        echo "10"; sleep 1
        echo "Installing base packages..."; sleep 1
        debug $DEBUG_DEBUG "Installing base packages from pkglist.txt"
        basestrap $INST_MNT - < misc/pkglist.txt >> "$LOG_FILE" 2>&1 && echo "50"
        
        echo "Installing kernel packages..."; sleep 1
        debug $DEBUG_DEBUG "Installing kernel: $INST_LINVAR"
        basestrap $INST_MNT $INST_LINVAR ${INST_LINVAR}-headers linux-firmware >> "$LOG_FILE" 2>&1 && echo "80"
        
        # Install ZFS packages if ZFS is selected
        if [[ $FILESYSTEM == "zfs" ]]; then
            echo "Installing ZFS packages..."; sleep 1
            debug $DEBUG_DEBUG "Installing ZFS packages from misc directory"
            basestrap $INST_MNT zfs-dkms-git zfs-utils-git
            basestrap -U $INST_MNT misc/zfs-openrc-*.pkg.tar.zst >> "$LOG_FILE" 2>&1 && echo "90"
        fi
        
        echo "Copying pacman configuration..."; sleep 1
        debug $DEBUG_DEBUG "Copying pacman configuration files"
        rm -rf $INST_MNT/etc/pacman.d >> "$LOG_FILE" 2>&1
        rm $INST_MNT/etc/pacman.conf >> "$LOG_FILE" 2>&1
        cp -r /etc/pacman.d $INST_MNT/etc >> "$LOG_FILE" 2>&1
        cp /etc/pacman.conf $INST_MNT/etc >> "$LOG_FILE" 2>&1 && echo "100"
    ) | dialog --gauge "Installing packages..." 10 70 0

    # Check if the packages were installed successfully
    if [[ $? -ne 0 ]]; then
        debug $DEBUG_ERROR "Package installation failed"
        error "Error installing packages!"
    fi

    debug $DEBUG_INFO "Package installation completed successfully"
    printf "%s\n" "${bold}Packages installed successfully!"
}