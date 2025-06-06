#!/usr/bin/env bash

error() {
    debug $DEBUG_ERROR "$1"
    printf "%s\n" "${bolderror}ERROR:${normal}\\n%s\\n" "$1" >&2
    exit 1
}

chaoticaur() {
    debug $DEBUG_INFO "Starting Chaotic AUR installation"
    printf "%s\n" "## Installing Chaotic AUR ##"

    # Start the progress bar
    (
        echo "10"; sleep 1
        echo "Receiving key for Chaotic AUR..."; sleep 1
        debug $DEBUG_DEBUG "Running: pacman-key --recv-key 8A9E14A07010F7E3"
        pacman-key --recv-key 8A9E14A07010F7E3 >> "$LOG_FILE" 2>&1 && echo "30"
        
        debug $DEBUG_DEBUG "Running: pacman-key --lsign-key 8A9E14A07010F7E3"
        pacman-key --lsign-key 8A9E14A07010F7E3 >> "$LOG_FILE" 2>&1 && echo "50"
        
        echo "Updating package database..."; sleep 1
        debug $DEBUG_DEBUG "Running: pacman -Sy"
        pacman -Sy >> "$LOG_FILE" 2>&1 && echo "70"
        
        echo "Installing Chaotic AUR keyring..."; sleep 1
        debug $DEBUG_DEBUG "Installing Chaotic keyring"
        yes | LC_ALL=en_US.UTF-8 pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' >> "$LOG_FILE" 2>&1 && echo "85"
        
        echo "Installing Chaotic AUR mirrorlist..."; sleep 1
        debug $DEBUG_DEBUG "Installing Chaotic mirrorlist"
        yes | LC_ALL=en_US.UTF-8 pacman -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' >> "$LOG_FILE" 2>&1 && echo "100"
    ) | dialog --gauge "Installing Chaotic AUR..." 10 70 0

    if [[ $? -ne 0 ]]; then
        debug $DEBUG_ERROR "Chaotic AUR installation failed"
        error "Error installing Chaotic AUR!"
    fi

    debug $DEBUG_INFO "Chaotic AUR installation completed successfully"
    printf "%s\n" "${bold}Chaotic AUR installed successfully!"
}

addrepo() {
    debug $DEBUG_INFO "Starting repository configuration"
    printf "%s\n" "## Adding repos to /etc/pacman.conf."

    # Start the progress bar
    (
        echo "10"; sleep 1
        echo "Installing artix-archlinux-support package..."; sleep 1
        debug $DEBUG_DEBUG "Running: pacman -Sy --noconfirm artix-archlinux-support"
        pacman -Sy --noconfirm artix-archlinux-support >> "$LOG_FILE" 2>&1 && echo "50"
        
        echo "Copying pacman.conf to /etc/..."; sleep 1
        debug $DEBUG_DEBUG "Copying pacman.conf to /etc/"
        cp misc/pacman.conf /etc/ >> "$LOG_FILE" 2>&1 && echo "100"
    ) | dialog --gauge "Adding repositories to pacman.conf..." 10 70 0

    if [[ $? -ne 0 ]]; then
        debug $DEBUG_ERROR "Repository configuration failed"
        error "Error adding repos!"
    fi

    debug $DEBUG_INFO "Repository configuration completed successfully"
    printf "%s\n" "${bold}Repositories added successfully!"
}