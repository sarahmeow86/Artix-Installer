#!/usr/bin/env bash
# Debug levels and colors
DEBUG_OFF=0; DEBUG_ERROR=1; DEBUG_WARN=2; DEBUG_INFO=3; DEBUG_DEBUG=4



bold=$(tput setaf 2 bold)
bolderror=$(tput setaf 3 bold)
normal=$(tput sgr0)

# Create chroot-specific log file
CHROOT_LOG="/var/log/artix-installer/chroot-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$CHROOT_LOG")"

bold=$(tput setaf 2 bold)      # makes text bold and sets color to 2
bolderror=$(tput setaf 3 bold) # makes text bold and sets color to 3
normal=$(tput sgr0)            # resets text settings back to normal

# Debug function
debug() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ $level -le $DEBUG_LEVEL ]]; then
        case $level in
            $DEBUG_ERROR)
                echo "[ERROR] [$timestamp] $message" >> "$CHROOT_LOG"
                ;;
            $DEBUG_WARN)
                echo "[WARN]  [$timestamp] $message" >> "$CHROOT_LOG"
                ;;
            $DEBUG_INFO)
                echo "[INFO]  [$timestamp] $message" >> "$CHROOT_LOG"
                ;;
            $DEBUG_DEBUG)
                echo "[DEBUG] [$timestamp] $message" >> "$CHROOT_LOG"
                ;;
        esac
    fi
}

error() {
    debug $DEBUG_ERROR "$1"
    printf "%s\n" "${bolderror}ERROR:${normal}\\n%s\\n" "$1" >&2
    exit 1
}

select_desktop_environment() {
    # Save original stdout and stderr
    exec 3>&1
    exec 4>&2
    
    debug $DEBUG_INFO "Starting desktop environment selection"

    # Create temporary file for dialog output
    temp_choice=$(mktemp)
    debug $DEBUG_DEBUG "Created temporary file: $temp_choice"

    # Display dialog to terminal
    dialog --clear --title "Desktop Environment Selection" \
        --menu "Choose a desktop environment to install:" 15 60 6 \
        1 "Base (No Desktop Environment)" \
        2 "Cinnamon" \
        3 "MATE" \
        4 "KDE Plasma" \
        5 "LXQt" \
        6 "XFCE" 2>"$temp_choice" >&3

    # Read user's choice
    DE_CHOICE=$(<"$temp_choice")
    rm -f "$temp_choice"
    debug $DEBUG_DEBUG "User selected DE choice: $DE_CHOICE"
    # Map the choice to the corresponding pkglist file and set DE name
    case $DE_CHOICE in
        1) 
            PKGLIST="pkglist-base.txt"
            DE="none"
            ;;
        2) 
            PKGLIST="pkglist-cinnamon.txt"
            DE="cinnamon"
            ;;
        3) 
            PKGLIST="pkglist-mate.txt"
            DE="mate"
            ;;
        4) 
            PKGLIST="pkglist-plasma.txt"
            DE="plasma"
            ;;
        5) 
            PKGLIST="pkglist-lxqt.txt"
            DE="lxqt"
            ;;
        6) 
            PKGLIST="pkglist-xfce.txt"
            DE="xfce"
            ;;
        *) 
            error "Invalid choice or no selection made!"
            ;;
    esac

    # Install packages from the selected pkglist
    if [[ -f "/install/$PKGLIST" ]]; then
        debug $DEBUG_INFO "Installing packages for $DE"
        dialog --infobox "Installing packages for $DE..." 5 50 >&3
        (
            echo "10" >&3; sleep 1
            debug $DEBUG_DEBUG "Starting package installation"
            echo "Installing packages..." >&3
            if pacman -Sy --noconfirm - < "/install/$PKGLIST" >> "$CHROOT_LOG" 2>&1; then
                debug $DEBUG_INFO "Package installation completed"
                echo "100" >&3
            else
                debug $DEBUG_ERROR "Package installation failed"
                error "Failed to install packages!"
            fi
        ) | dialog --gauge "Installing $DE packages..." 10 70 0 >&3
    else
        debug $DEBUG_ERROR "Package list not found: /install/$PKGLIST"
        error "Package list file not found!"
    fi

    # Restore original stdout and stderr
    exec 1>&3
    exec 2>&4
    exec 3>&-
    exec 4>&-

    debug $DEBUG_INFO "Desktop environment setup completed"
    printf "%s\n" "${bold}Desktop environment $DE installed successfully!"
    export DE
}

# Function to detect the root filesystem
detect_root_filesystem() {
    debug $DEBUG_INFO "Starting root filesystem detection"
    ROOT_FS=$(findmnt -n -o FSTYPE /)
    if [[ -z "$ROOT_FS" ]]; then
        debug $DEBUG_ERROR "Failed to detect root filesystem"
        error "Failed to detect the root filesystem!"
    fi
    debug $DEBUG_INFO "Root filesystem detected: $ROOT_FS"
    printf "%s\n" "${bold}Detected root filesystem: $ROOT_FS"
}

# Function to install and configure GRUB
install_grub() {
    debug $DEBUG_INFO "Starting GRUB installation"
    dialog --infobox "Installing and configuring GRUB bootloader..." 5 50 >&3
    (
        echo "10" >&3; sleep 1
        debug $DEBUG_DEBUG "Installing GRUB packages"
        echo "Installing GRUB and related packages..." >&3; sleep 1
        pacman -S --noconfirm grub os-prober efibootmgr >> "$CHROOT_LOG" 2>&1 || error "Failed to install GRUB packages!" && echo "50" >&3
        
        debug $DEBUG_DEBUG "Installing GRUB to EFI partition"
        echo "Installing GRUB to EFI system partition..." >&3; sleep 1
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB >> "$CHROOT_LOG" 2>&1 || error "Failed to install GRUB!" && echo "80" >&3
        
        debug $DEBUG_DEBUG "Generating GRUB configuration"
        echo "Generating GRUB configuration file..." >&3; sleep 1
        grub-mkconfig -o /boot/grub/grub.cfg >> "$CHROOT_LOG" 2>&1 || error "Failed to generate GRUB configuration!" && echo "100" >&3
    ) | dialog --gauge "Installing GRUB bootloader..." 10 70 0 >&3

    debug $DEBUG_INFO "GRUB installation completed"
    dialog --msgbox "GRUB has been installed and configured successfully!" 10 50 >&3
}


# Function to install and configure ZFSBootMenu
install_zfsbootmenu() {
    # Save original stdout and stderr
    exec 3>&1
    exec 4>&2
    
    debug $DEBUG_INFO "Starting ZFSBootMenu installation"
    dialog --infobox "Installing ZFSBootMenu..." 5 50 >&3
    (
        echo "10" >&3; sleep 1
        debug $DEBUG_DEBUG "Creating ZFSBootMenu directory"
        echo "Creating ZFSBootMenu directory..." >&3; sleep 1
        mkdir -p /boot/efi/EFI/BOOT >> "$CHROOT_LOG" 2>&1 && echo "30" >&3

        debug $DEBUG_DEBUG "Downloading ZFSBootMenu EFI file"
        echo "Downloading ZFSBootMenu EFI file..." >&3; sleep 1
        curl -L https://get.zfsbootmenu.org/efi -o /boot/efi/EFI/BOOT/BOOTX64.EFI >> "$CHROOT_LOG" 2>&1 && echo "70" >&3

        debug $DEBUG_DEBUG "Configuring EFI boot entry"
        echo "Configuring EFI boot entry..." >&3; sleep 1
        efibootmgr --disk $(findmnt -n -o SOURCE /boot/efi | sed 's/[0-9]*$//') --part 1 \
            --create --label "ZFSBootMenu" \
            --loader '\EFI\BOOT\BOOTX64.EFI' \
            --unicode "spl_hostid=$(hostid) zbm.timeout=3 zbm.prefer=$ZFS_POOL_NAME zbm.import_policy=hostid" \
            --verbose >> "$CHROOT_LOG" 2>&1 && echo "100" >&3
    ) | dialog --gauge "Installing ZFSBootMenu..." 10 70 0 >&3

    if [[ $? -ne 0 ]]; then
        debug $DEBUG_ERROR "ZFSBootMenu installation failed"
        error "Failed to install ZFSBootMenu!"
    fi

    debug $DEBUG_INFO "ZFSBootMenu installation completed"
    dialog --msgbox "ZFSBootMenu has been installed and configured successfully!" 10 50 >&3

    # Restore original stdout and stderr
    exec 1>&3
    exec 2>&4
    exec 3>&-
    exec 4>&-
}

zfsservice() {
    # Save original stdout and stderr
    exec 3>&1
    exec 4>&2
    
    debug $DEBUG_INFO "Starting ZFS service configuration"
    # Start the progress bar
    (
        echo "10" >&3; sleep 1
        debug $DEBUG_DEBUG "Installing ZFS OpenRC package"
        echo "Installing ZFS OpenRC package..." >&3; sleep 1
        pacman -U --noconfirm /install/zfs-openrc-20241023-1-any.pkg.tar.zst >> "$CHROOT_LOG" 2>&1 && echo "30" >&3

        debug $DEBUG_DEBUG "Adding ZFS services to boot runlevel"
        local services=("zfs-import" "zfs-load-key" "zfs-share" "zfs-zed" "zfs-mount")
        local current=40
        local step=10

        for service in "${services[@]}"; do
            echo "Adding $service service to boot..." >&3; sleep 1
            debug $DEBUG_DEBUG "Adding service: $service"
            rc-update add "$service" boot >> "$CHROOT_LOG" 2>&1 && echo "$current" >&3
            ((current += step))
        done
    ) | dialog --gauge "Configuring ZFS services..." 10 70 0 >&3

    if [[ $? -ne 0 ]]; then
        debug $DEBUG_ERROR "ZFS service configuration failed"
        error "Error configuring ZFS services!"
    fi

    debug $DEBUG_INFO "ZFS services configured successfully"
    printf "%s\n" "${bold}ZFS services configured successfully!"

    # Restore original stdout and stderr
    exec 1>&3
    exec 2>&4
    exec 3>&-
    exec 4>&-
}

cachefile() {
    debug $DEBUG_INFO "Starting ZFS cache file creation"
    # Start the progress bar
    (
        echo "10" >&3; sleep 1
        debug $DEBUG_DEBUG "Setting ZFS cachefile location"
        echo "Setting ZFS cachefile..." >&3; sleep 1
        zpool set cachefile=/etc/zfs/zpool.cache "$ZFS_POOL_NAME" >> "$CHROOT_LOG" 2>&1 && echo "100" >&3
        
    ) | dialog --gauge "Setting ZFS cachefile..." 10 70 0

    # Verify the cachefile was set
    if ! zpool get cachefile "$ZFS_POOL_NAME" | grep -q "/etc/zfs/zpool.cache"; then
        debug $DEBUG_ERROR "Failed to set ZFS cachefile"
        error "Error setting ZFS cachefile!"
    fi

    debug $DEBUG_INFO "ZFS cachefile set successfully"
    printf "%s\n" "${bold}ZFS cachefile set successfully!"
}

regenerate_initcpio() {
    debug $DEBUG_INFO "Starting initramfs regeneration"
    # Start the progress bar
    (
        echo "10" >&3; sleep 1
        debug $DEBUG_DEBUG "Backing up existing initramfs"
        echo "Backing up existing initramfs..." >&3; sleep 1
        cp /boot/initramfs-linux.img /boot/initramfs-linux.img.bak >> "$CHROOT_LOG" 2>&1 && echo "30" >&3
        
        debug $DEBUG_DEBUG "Regenerating initramfs"
        echo "Regenerating initramfs..." >&3; sleep 1
        mkinitcpio -P >> "$CHROOT_LOG" 2>&1 && echo "100" >&3
    ) | dialog --gauge "Regenerating initramfs..." 10 70 0 >&3

    if [[ $? -ne 0 ]]; then
        debug $DEBUG_ERROR "Initramfs regeneration failed"
        error "Error regenerating initramfs!"
    fi

    debug $DEBUG_INFO "Initramfs regenerated successfully"
    printf "%s\n" "${bold}Initramfs regenerated successfully!"
}

configure_bootloader() {
    debug $DEBUG_INFO "Starting bootloader configuration"
    detect_root_filesystem
    
    if [[ "$ROOT_FS" == "zfs" ]]; then
        debug $DEBUG_DEBUG "Configuring ZFSBootMenu for ZFS root"
        install_zfsbootmenu && zfsservice && cachefile && regenerate_initcpio || {
            debug $DEBUG_ERROR "ZFSBootMenu installation failed"
            error "Error installing ZFSBootMenu!"
        }
    else
        debug $DEBUG_DEBUG "Configuring GRUB for standard root"
        install_grub && regenerate_initcpio || {
            debug $DEBUG_ERROR "GRUB installation failed"
            error "Error installing GRUB!"
        }
    fi
    debug $DEBUG_INFO "Bootloader configuration completed"
}

addlocales() {
    debug $DEBUG_INFO "Starting locale configuration"
    locale_list=$(grep -v '^$' /install/locale.gen | awk '{print $1}' | sort)
    dialog_options=()
    
    debug $DEBUG_DEBUG "Building locale list"
    while IFS= read -r locale; do
        dialog_options+=("$locale" "$locale")
    done <<< "$locale_list"

    debug $DEBUG_DEBUG "Displaying locale selection dialog"
    alocale=$(dialog --clear --title "Locale Selection" \
        --menu "Choose your locale from the list:" 20 70 15 "${dialog_options[@]}" 3>&1 1>&2 2>&3)

    if [[ -z "$alocale" ]]; then
        debug $DEBUG_WARN "No locale selected"
        printf "%s\n" "No locale selected. Skipping locale configuration."
        return 0
    fi

    debug $DEBUG_DEBUG "Configuring selected locale: $alocale"
    sed -i "s/^#\s*\($alocale\)/\1/" /etc/locale.gen >> "$CHROOT_LOG" 2>&1
    locale-gen >> "$CHROOT_LOG" 2>&1 || {
        debug $DEBUG_ERROR "Locale generation failed"
        error "Failed to generate locale!"
    }

    debug $DEBUG_INFO "Locale configuration completed"
    printf "%s\n" "${bold}Locale '$alocale' has been added and generated successfully!"
}

setlocale() {
    debug $DEBUG_INFO "Setting system locale to $alocale"
    printf "%s\n" "${bold}Setting locale to $alocale"
    echo "LANG=$alocale" > /etc/locale.conf || {
        debug $DEBUG_ERROR "Failed to set locale"
        error "Cannot set locale!"
    }
    debug $DEBUG_INFO "System locale set successfully"
}

USERADD() {
    debug $DEBUG_INFO "Starting user account creation"
    username=$(dialog --clear --title "Create User Account" \
        --inputbox "Enter the non-root username:" 10 50 3>&1 1>&2 2>&3)

    if [[ -z "$username" ]]; then
        debug $DEBUG_ERROR "No username provided"
        error "No username provided!"
    fi

    debug $DEBUG_DEBUG "Creating user: $username"
    useradd -m -G audio,video,wheel "$username" >> "$CHROOT_LOG" 2>&1 || {
        debug $DEBUG_ERROR "User creation failed"
        error "Failed to add user $username"
    }

    debug $DEBUG_DEBUG "Setting password for user: $username"
    password=$(dialog --clear --title "Set User Password" \
        --passwordbox "Enter the password for $username:" 10 50 3>&1 1>&2 2>&3)

    if [[ -z "$password" ]]; then
        debug $DEBUG_ERROR "No password provided"
        error "No password provided!"
    fi

    echo "$username:$password" | chpasswd >> "$CHROOT_LOG" 2>&1 || {
        debug $DEBUG_ERROR "Password set failed"
        error "Failed to set password for $username"
    }

    debug $DEBUG_INFO "User account created successfully"
    printf "%s\n" "${bold}User $username has been created successfully!"
}

passwdroot() {
    debug $DEBUG_INFO "Starting root password configuration"
    
    # Get root password
    rootpass=$(dialog --clear --title "Set Root Password" \
        --passwordbox "Enter the password for root:" 10 50 3>&1 1>&2 2>&3)

    if [[ -z "$rootpass" ]]; then
        debug $DEBUG_ERROR "No root password provided"
        error "No root password provided!"
    fi

    # Confirm root password
    rootpass_confirm=$(dialog --clear --title "Confirm Root Password" \
        --passwordbox "Confirm the password for root:" 10 50 3>&1 1>&2 2>&3)

    if [[ "$rootpass" != "$rootpass_confirm" ]]; then
        debug $DEBUG_ERROR "Root passwords do not match"
        error "Passwords do not match!"
    fi

    debug $DEBUG_DEBUG "Setting root password"
    echo "root:$rootpass" | chpasswd >> "$CHROOT_LOG" 2>&1 || {
        debug $DEBUG_ERROR "Root password set failed"
        error "Failed to set root password"
    }

    debug $DEBUG_INFO "Root password configured successfully"
    printf "%s\n" "${bold}Root password has been set successfully!"
}

enable_boot_services() {
    local boot_services_file="/install/services/boot-runtime-${DE}.txt"
    debug $DEBUG_DEBUG "Processing boot services"

    if [[ ! -f "$boot_services_file" ]]; then
        debug $DEBUG_ERROR "Boot services file not found: $boot_services_file"
        error "Boot services file not found: $boot_services_file"
    fi

    echo "Adding boot runlevel services..." >&3; sleep 1
    while IFS= read -r service; do
        # Skip empty lines and comments
        [[ -z "$service" || "$service" =~ ^# ]] && continue
        
        # Check if service exists
        if ! rc-service --exists "$service"; then
            debug $DEBUG_ERROR "Service $service does not exist"
            continue
        fi

        # Check if service is already enabled
        if rc-update show boot | grep -q "^[[:space:]]*$service\$"; then
            debug $DEBUG_DEBUG "Service $service already enabled in boot runlevel"
            continue
        fi

        debug $DEBUG_DEBUG "Adding boot service: $service"
        if ! rc-update add "$service" boot >> "$CHROOT_LOG" 2>&1; then
            debug $DEBUG_ERROR "Failed to enable service: $service"
            error "Failed to enable service: $service"
        fi
    done < "$boot_services_file"
    debug $DEBUG_INFO "Boot services configured successfully"
}

enable_default_services() {
    local default_services_file="/install/services/default-runtime-${DE}.txt"
    debug $DEBUG_DEBUG "Processing default services"

    if [[ ! -f "$default_services_file" ]]; then
        debug $DEBUG_ERROR "Default services file not found: $default_services_file"
        error "Default services file not found: $default_services_file"
    fi

    echo "Adding default runlevel services..." >&3; sleep 1
    while IFS= read -r service; do
        # Skip empty lines and comments
        [[ -z "$service" || "$service" =~ ^# ]] && continue
        
        # Check if service exists
        if ! rc-service --exists "$service"; then
            debug $DEBUG_ERROR "Service $service does not exist"
            continue
        fi

        # Check if service is already enabled
        if rc-update show default | grep -q "^[[:space:]]*$service\$"; then
            debug $DEBUG_DEBUG "Service $service already enabled in default runlevel"
            continue
        fi

        debug $DEBUG_DEBUG "Adding default service: $service"
        if ! rc-update add "$service" default >> "$CHROOT_LOG" 2>&1; then
            debug $DEBUG_ERROR "Failed to enable service: $service"
            error "Failed to enable service: $service"
        fi
    done < "$default_services_file"
    debug $DEBUG_INFO "Default services configured successfully"
}

enableservices() {
    # Save original stdout and stderr
    exec 3>&1
    exec 4>&2

    debug $DEBUG_INFO "Starting service configuration for $DE"
    printf "%s\n" "${bold}Enabling services for ${DE}"

    # Start the progress bar
    (
        echo "5" >&3; sleep 1
        
        # Enable boot services
        enable_boot_services
        echo "40" >&3

        # Enable default services
        enable_default_services
        echo "70" >&3

        # Verify services were enabled correctly
        echo "Verifying services..." >&3; sleep 1
        debug $DEBUG_DEBUG "Verifying enabled services"
        rc-update show >> "$CHROOT_LOG" 2>&1 && echo "100" >&3
        
    ) | dialog --gauge "Enabling system services..." 10 70 0 >&3

    debug $DEBUG_INFO "Services configured successfully"
    printf "%s\n" "${bold}Services enabled successfully!"

    # Restore original stdout and stderr
    exec 1>&3
    exec 2>&4
    exec 3>&-
    exec 4>&-
}

main() {
    debug $DEBUG_INFO "Starting main installation process"
    # Save original stdout and stderr
    exec 3>&1
    exec 4>&2

    debug $DEBUG_DEBUG "Starting desktop environment setup"
    select_desktop_environment || {
        debug $DEBUG_ERROR "Desktop environment selection failed"
        error "Error selecting desktop environment!"
    }

    debug $DEBUG_DEBUG "Starting locale configuration"
    addlocales || {
        debug $DEBUG_ERROR "Locale generation failed"
        error "Cannot generate locales"
    }
    setlocale || {
        debug $DEBUG_ERROR "Locale setup failed"
        error "Cannot set locale"
    }

    debug $DEBUG_DEBUG "Starting user account setup"
    USERADD || {
        debug $DEBUG_ERROR "User creation failed"
        error "Error adding user to your install"
    }
    passwdroot || {
        debug $DEBUG_ERROR "Root password setup failed"
        error "Error setting root password!"
    }

    debug $DEBUG_DEBUG "Starting service configuration"
    enableservices || {
        debug $DEBUG_ERROR "Service configuration failed"
        error "Error enabling services!"
    }

    debug $DEBUG_DEBUG "Starting bootloader configuration"
    configure_bootloader || {
        debug $DEBUG_ERROR "Bootloader configuration failed"
        error "Error configuring bootloader!"
    }

    debug $DEBUG_INFO "Installation completed successfully"
    # Display completion message
    dialog --title "Installation Complete" --msgbox "\
${bold}Finish!${normal}\n\n\
The installation process has been completed successfully." 10 50 >&3

    # Restore original stdout and stderr
    exec 1>&3
    exec 2>&4
    exec 3>&-
    exec 4>&-

    debug $DEBUG_INFO "Main process completed"
}

# Execute main function with logging
debug $DEBUG_INFO "Starting main execution"
main