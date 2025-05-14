#!/usr/bin/env bash
# Debug levels
DEBUG_OFF=0; DEBUG_ERROR=1; DEBUG_WARN=2; DEBUG_INFO=3; DEBUG_DEBUG=4
DEBUG_LEVEL=${DEBUG_LEVEL:-$DEBUG_ERROR}  # Default to ERROR if not set


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
    debug $DEBUG_INFO "Starting desktop environment selection"
    # Save original descriptors
    exec 3>&1
    exec 4>&2

    # Create temporary file for dialog output
    temp_choice=$(mktemp)
    debug $DEBUG_DEBUG "Created temporary choice file: $temp_choice"

    # Display dialog menu
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
            exec 1>&3 2>&4
            error "Invalid choice or no selection made!"
            ;;
    esac

    # Install packages from the selected pkglist
    if [[ -f "/install/$PKGLIST" ]]; then
        debug $DEBUG_INFO "Installing packages for $DE"
        dialog --infobox "Installing packages for $DE..." 5 50 >&3
        (
            echo "10" >&3; sleep 1
            echo "Installing packages..." >&3
            debug $DEBUG_DEBUG "Running pacman to install packages"
            if pacman -Sy --noconfirm - < "/install/$PKGLIST" >/dev/null 2>&4; then
                debug $DEBUG_INFO "Package installation completed successfully"
                echo "100" >&3
            else
                debug $DEBUG_ERROR "Package installation failed"
                exec 1>&3 2>&4
                error "Failed to install packages!"
            fi
        ) | dialog --gauge "Installing $DE packages..." 10 70 0 >&3
    else
        debug $DEBUG_ERROR "Package list not found: /install/$PKGLIST"
        exec 1>&3 2>&4
        error "Package list file not found!"
    fi

    # Restore original descriptors
    exec 1>&3 2>&4
    exec 3>&- 4>&-

    printf "%s\n" "${bold}Desktop environment $DE installed successfully!"
    export DE
}

detect_root_filesystem() {
    debug $DEBUG_INFO "Detecting root filesystem"
    ROOT_FS=$(findmnt -n -o FSTYPE /)
    if [[ -z "$ROOT_FS" ]]; then
        debug $DEBUG_ERROR "Failed to detect root filesystem"
        error "Failed to detect the root filesystem!"
    fi
    debug $DEBUG_INFO "Found root filesystem: $ROOT_FS"
    
    if [[ "$ROOT_FS" == "zfs" ]]; then
        debug $DEBUG_INFO "ZFS filesystem detected, getting pool name"
        ZFS_POOL_NAME=$(zfs list -H -o name / | cut -d'/' -f1)
        if [[ -z "$ZFS_POOL_NAME" ]]; then
            debug $DEBUG_ERROR "Failed to detect ZFS pool name"
            error "Failed to detect the ZFS pool name!"
        fi
        debug $DEBUG_INFO "Found ZFS pool name: $ZFS_POOL_NAME"
        export ZFS_POOL_NAME
    fi
    
    printf "%s\n" "${bold}Detected root filesystem: $ROOT_FS"
}

install_grub() {
    debug $DEBUG_INFO "Starting GRUB installation"
    exec 3>&1 4>&2
    
    dialog --infobox "Installing and configuring GRUB bootloader..." 5 50 >&3
    (
        echo "10" >&3; sleep 1
        debug $DEBUG_INFO "Installing GRUB packages"
        echo "Installing GRUB and related packages..." >&3
        if ! pacman -S --noconfirm grub os-prober efibootmgr >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to install GRUB packages"
            exec 1>&3 2>&4
            error "Failed to install GRUB packages!"
        fi
        echo "50" >&3
        
        debug $DEBUG_INFO "Installing GRUB to EFI partition"
        echo "Installing GRUB to EFI system partition..." >&3
        if ! grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to install GRUB to EFI partition"
            exec 1>&3 2>&4
            error "Failed to install GRUB!"
        fi
        echo "80" >&3
        
        debug $DEBUG_INFO "Generating GRUB configuration"
        echo "Generating GRUB configuration file..." >&3
        if ! grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to generate GRUB configuration"
            exec 1>&3 2>&4
            error "Failed to generate GRUB configuration!"
        fi
        echo "100" >&3
        debug $DEBUG_INFO "GRUB installation completed successfully"
    ) | dialog --gauge "Installing GRUB bootloader..." 10 70 0 >&3

    dialog --msgbox "GRUB has been installed and configured successfully!" 10 50 >&3
    
    exec 1>&3 2>&4 3>&- 4>&-
}

install_zfsbootmenu() {
    debug $DEBUG_INFO "Starting ZFSBootMenu installation"
    exec 3>&1 4>&2
    
    dialog --infobox "Installing ZFSBootMenu..." 5 50 >&3
    (
        echo "10" >&3; sleep 1
        debug $DEBUG_INFO "Creating ZFSBootMenu directory"
        echo "Creating ZFSBootMenu directory..." >&3
        if ! mkdir -p /boot/efi/EFI/BOOT >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to create ZFSBootMenu directory"
            exec 1>&3 2>&4
            error "Failed to create ZFSBootMenu directory!"
        fi
        echo "30" >&3

        debug $DEBUG_INFO "Downloading ZFSBootMenu EFI file"
        echo "Downloading ZFSBootMenu EFI file..." >&3
        if ! curl -L https://get.zfsbootmenu.org/efi -o /boot/efi/EFI/BOOT/BOOTX64.EFI >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to download ZFSBootMenu EFI file"
            exec 1>&3 2>&4
            error "Failed to download ZFSBootMenu EFI file!"
        fi
        echo "70" >&3

        debug $DEBUG_INFO "Configuring EFI boot entry"
        echo "Configuring EFI boot entry..." >&3
        if ! efibootmgr --disk $(findmnt -n -o SOURCE /boot/efi | sed 's/[0-9]*$//') --part 1 \
            --create --label "ZFSBootMenu" \
            --loader '\EFI\BOOT\BOOTX64.EFI' \
            --unicode "spl_hostid=$(hostid) zbm.timeout=3 zbm.prefer=$ZFS_POOL_NAME zbm.import_policy=hostid" \
            --verbose >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to configure EFI boot entry"
            exec 1>&3 2>&4
            error "Failed to configure EFI boot entry!"
        fi
        echo "100" >&3
        debug $DEBUG_INFO "ZFSBootMenu installation completed successfully"
    ) | dialog --gauge "Installing ZFSBootMenu..." 10 70 0 >&3

    dialog --msgbox "ZFSBootMenu has been installed and configured successfully!" 10 50 >&3
    
    exec 1>&3 2>&4 3>&- 4>&-
}

zfsservice() {
    debug $DEBUG_INFO "Configuring ZFS services"
    exec 3>&1 4>&2
    
    (
        echo "10" >&3; sleep 1
        debug $DEBUG_INFO "Installing ZFS OpenRC package"
        echo "Installing ZFS OpenRC package..." >&3
        if ! pacman -U --noconfirm /install/zfs-openrc-20241023-1-any.pkg.tar.zst >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to install ZFS OpenRC package"
            exec 1>&3 2>&4
            error "Failed to install ZFS OpenRC package!"
        fi
        echo "30" >&3

        local services=("zfs-import" "zfs-load-key" "zfs-share" "zfs-zed" "zfs-mount")
        local current=40
        local step=10

        for service in "${services[@]}"; do
            debug $DEBUG_INFO "Adding $service service to boot"
            echo "Adding $service service to boot..." >&3
            if ! rc-update add "$service" boot >/dev/null 2>&4; then
                debug $DEBUG_ERROR "Failed to add $service service to boot"
                exec 1>&3 2>&4
                error "Failed to add $service service to boot!"
            fi
            echo "$current" >&3
            ((current += step))
        done
        debug $DEBUG_INFO "ZFS services configuration completed successfully"
    ) | dialog --gauge "Configuring ZFS services..." 10 70 0 >&3

    printf "%s\n" "${bold}ZFS services configured successfully!"
    
    exec 1>&3 2>&4 3>&- 4>&-
}

regenerate_initcpio() {
    debug $DEBUG_INFO "Regenerating initramfs"
    exec 3>&1 4>&2
    
    (
        echo "10" >&3; sleep 1
        debug $DEBUG_INFO "Backing up existing initramfs"
        echo "Backing up existing initramfs..." >&3
        if ! cp /boot/initramfs-linux.img /boot/initramfs-linux.img.bak >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to back up existing initramfs"
            exec 1>&3 2>&4
            error "Failed to back up existing initramfs!"
        fi
        echo "30" >&3
        
        debug $DEBUG_INFO "Regenerating initramfs"
        echo "Regenerating initramfs..." >&3
        if ! mkinitcpio -P >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to regenerate initramfs"
            exec 1>&3 2>&4
            error "Failed to regenerate initramfs!"
        fi
        echo "100" >&3
        debug $DEBUG_INFO "Initramfs regeneration completed successfully"
    ) | dialog --gauge "Regenerating initramfs..." 10 70 0 >&3

    printf "%s\n" "${bold}Initramfs regenerated successfully!"
    
    exec 1>&3 2>&4 3>&- 4>&-
}

configure_bootloader() {
    debug $DEBUG_INFO "Configuring bootloader"
    detect_root_filesystem
    
    if [[ "$ROOT_FS" == "zfs" ]]; then
        install_zfsbootmenu && zfsservice && regenerate_initcpio || {
            error "Error installing ZFSBootMenu!"
        }
    else
        install_grub && regenerate_initcpio || {
            error "Error installing GRUB!"
        }
    fi
}

addlocales() {
    debug $DEBUG_INFO "Adding locales"
    exec 3>&1 4>&2
    
    locale_list=$(grep -v '^$' /install/locale.gen | awk '{print $1}' | sort)
    dialog_options=()
    
    while IFS= read -r locale; do
        dialog_options+=("$locale" "$locale")
    done <<< "$locale_list"

    alocale=$(dialog --clear --title "Locale Selection" \
        --menu "Choose your locale from the list:" 20 70 15 "${dialog_options[@]}" 2>&1 1>&3)

    if [[ -z "$alocale" ]]; then
        printf "%s\n" "No locale selected. Skipping locale configuration."
        exec 1>&3 2>&4 3>&- 4>&-
        return 0
    fi

    debug $DEBUG_INFO "Selected locale: $alocale"
    sed -i "s/^#\s*\($alocale\)/\1/" /etc/locale.gen >/dev/null 2>&4
    if ! locale-gen >/dev/null 2>&4; then
        debug $DEBUG_ERROR "Failed to generate locale"
        exec 1>&3 2>&4
        error "Failed to generate locale!"
    fi

    printf "%s\n" "${bold}Locale '$alocale' has been added and generated successfully!"
    
    exec 1>&3 2>&4 3>&- 4>&-
}

setlocale() {
    debug $DEBUG_INFO "Setting locale to $alocale"
    exec 3>&1 4>&2
    
    printf "%s\n" "${bold}Setting locale to $alocale"
    if ! echo "LANG=$alocale" > /etc/locale.conf >/dev/null 2>&4; then
        debug $DEBUG_ERROR "Failed to set locale"
        exec 1>&3 2>&4
        error "Cannot set locale!"
    fi
    
    exec 1>&3 2>&4 3>&- 4>&-
}

USERADD() {
    debug $DEBUG_INFO "Creating user account"
    exec 3>&1 4>&2
    
    username=$(dialog --clear --title "Create User Account" \
        --inputbox "Enter the non-root username:" 10 50 2>&1 1>&3)

    if [[ -z "$username" ]]; then
        debug $DEBUG_ERROR "No username provided"
        exec 1>&3 2>&4
        error "No username provided!"
    fi

    debug $DEBUG_INFO "Adding user $username"
    if ! useradd -m -G audio,video,wheel "$username" >/dev/null 2>&4; then
        debug $DEBUG_ERROR "Failed to add user $username"
        exec 1>&3 2>&4
        error "Failed to add user $username"
    fi

    password=$(dialog --clear --title "Set User Password" \
        --passwordbox "Enter the password for $username:" 10 50 2>&1 1>&3)

    if [[ -z "$password" ]]; then
        debug $DEBUG_ERROR "No password provided"
        exec 1>&3 2>&4
        error "No password provided!"
    fi

    debug $DEBUG_INFO "Setting password for user $username"
    if ! echo "$username:$password" | chpasswd >/dev/null 2>&4; then
        debug $DEBUG_ERROR "Failed to set password for $username"
        exec 1>&3 2>&4
        error "Failed to set password for $username"
    fi

    printf "%s\n" "${bold}User $username has been created successfully!"
    
    exec 1>&3 2>&4 3>&- 4>&-
}

passwdroot() {
    debug $DEBUG_INFO "Setting root password"
    exec 3>&1 4>&2
    
    rootpass=$(dialog --clear --title "Set Root Password" \
        --passwordbox "Enter the password for root:" 10 50 2>&1 1>&3)

    if [[ -z "$rootpass" ]]; then
        debug $DEBUG_ERROR "No root password provided"
        exec 1>&3 2>&4
        error "No root password provided!"
    fi

    rootpass_confirm=$(dialog --clear --title "Confirm Root Password" \
        --passwordbox "Confirm the password for root:" 10 50 2>&1 1>&3)

    if [[ "$rootpass" != "$rootpass_confirm" ]]; then
        debug $DEBUG_ERROR "Root passwords do not match"
        exec 1>&3 2>&4
        error "Passwords do not match!"
    fi

    debug $DEBUG_INFO "Setting root password"
    if ! echo "root:$rootpass" | chpasswd >/dev/null 2>&4; then
        debug $DEBUG_ERROR "Failed to set root password"
        exec 1>&3 2>&4
        error "Failed to set root password"
    fi

    printf "%s\n" "${bold}Root password has been set successfully!"
    
    exec 1>&3 2>&4 3>&- 4>&-
}

enable_boot_services() {
    debug $DEBUG_INFO "Starting boot services configuration"
    exec 3>&1 4>&2
    
    local boot_services_file="/install/services/boot-runtime-${DE}.txt"
    debug $DEBUG_DEBUG "Using boot services file: $boot_services_file"

    if [[ ! -f "$boot_services_file" ]]; then
        debug $DEBUG_ERROR "Boot services file not found: $boot_services_file"
        exec 1>&3 2>&4
        error "Boot services file not found: $boot_services_file"
    fi

    while IFS= read -r service; do
        [[ -z "$service" || "$service" =~ ^# ]] && continue
        
        debug $DEBUG_DEBUG "Processing service: $service"
        if ! rc-service --exists "$service"; then
            debug $DEBUG_WARN "Service $service does not exist, skipping"
            continue
        fi

        if rc-update show boot | grep -q "^[[:space:]]*$service\$"; then
            debug $DEBUG_DEBUG "Service $service already enabled in boot runlevel"
            continue
        fi

        debug $DEBUG_INFO "Enabling service $service in boot runlevel"
        if ! rc-update add "$service" boot >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to enable service: $service"
            exec 1>&3 2>&4
            error "Failed to enable service: $service"
        fi
        debug $DEBUG_INFO "Successfully enabled service: $service"
    done < "$boot_services_file"
    
    debug $DEBUG_INFO "Boot services configuration completed"
    exec 1>&3 2>&4 3>&- 4>&-
}

enable_default_services() {
    debug $DEBUG_INFO "Starting default services configuration"
    exec 3>&1 4>&2
    
    local default_services_file="/install/services/default-runtime-${DE}.txt"
    debug $DEBUG_DEBUG "Using default services file: $default_services_file"

    if [[ ! -f "$default_services_file" ]]; then
        debug $DEBUG_ERROR "Default services file not found: $default_services_file"
        exec 1>&3 2>&4
        error "Default services file not found: $default_services_file"
    fi

    while IFS= read -r service; do
        [[ -z "$service" || "$service" =~ ^# ]] && continue
        
        debug $DEBUG_DEBUG "Processing service: $service"
        if ! rc-service --exists "$service"; then
            debug $DEBUG_WARN "Service $service does not exist, skipping"
            continue
        fi

        if rc-update show default | grep -q "^[[:space:]]*$service\$"; then
            debug $DEBUG_DEBUG "Service $service already enabled in default runlevel"
            continue
        fi

        debug $DEBUG_INFO "Enabling service $service in default runlevel"
        if ! rc-update add "$service" default >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to enable service: $service"
            exec 1>&3 2>&4
            error "Failed to enable service: $service"
        fi
        debug $DEBUG_INFO "Successfully enabled service: $service"
    done < "$default_services_file"
    
    debug $DEBUG_INFO "Default services configuration completed"
    exec 1>&3 2>&4 3>&- 4>&-
}

enableservices() {
    debug $DEBUG_INFO "Starting services configuration for $DE"
    exec 3>&1 4>&2
    
    printf "%s\n" "${bold}Enabling services for ${DE}"

    (
        echo "5" >&3; sleep 1
        
        debug $DEBUG_INFO "Configuring boot services"
        echo "Enabling boot services..." >&3
        enable_boot_services
        echo "40" >&3

        debug $DEBUG_INFO "Configuring default services"
        echo "Enabling default services..." >&3
        enable_default_services
        echo "70" >&3

        debug $DEBUG_INFO "Verifying service configuration"
        echo "Verifying services..." >&3; sleep 1
        if ! rc-update show >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Service verification failed"
            exec 1>&3 2>&4
            error "Failed to verify services!"
        fi
        echo "100" >&3
        debug $DEBUG_INFO "Service configuration completed successfully"
    ) | dialog --gauge "Enabling system services..." 10 70 0 >&3

    printf "%s\n" "${bold}Services enabled successfully!"
    
    exec 1>&3 2>&4 3>&- 4>&-
}

main() {
    debug $DEBUG_INFO "Starting main installation process"
    exec 3>&1 4>&2
    
    select_desktop_environment || error "Error selecting desktop environment!"
    addlocales || error "Cannot generate locales"
    setlocale || error "Cannot set locale"
    USERADD || error "Error adding user to your install"
    passwdroot || error "Error setting root password!"
    enableservices || error "Error enabling services!"
    configure_bootloader || error "Error configuring bootloader!"

    debug $DEBUG_INFO "Installation completed successfully"
    dialog --title "Installation Complete" --msgbox "\
${bold}Finish!${normal}\n\n\
The installation process has been completed successfully." 10 50 >&3

    exec 1>&3 2>&4 3>&- 4>&-
}

debug $DEBUG_INFO "Script initialization complete"
main