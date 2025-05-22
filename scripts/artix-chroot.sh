#!/usr/bin/env bash
# Debug levels
DEBUG_OFF=0; DEBUG_ERROR=1; DEBUG_WARN=2; DEBUG_INFO=3; DEBUG_DEBUG=4
DEBUG_LEVEL=${DEBUG_LEVEL:-$DEBUG_INFO}  # Default to INFO if not set


# Create chroot-specific log file
CHROOT_LOG="/var/log/artix-installer/chroot-$(date +%Y%m%d-%H%M%S).log"
mkdir -p "$(dirname "$CHROOT_LOG")"

bold=$(tput setaf 2 bold)      # makes text bold and sets color to 2
bolderror=$(tput setaf 3 bold) # makes text bold and sets color to 3
normal=$(tput sgr0)            # resets text settings back to normal

# Save original file descriptors
exec 3>&1
exec 4>&2

# Add function to restore descriptors
restore_descriptors() {
    exec 1>&3
    exec 2>&4
}

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
    restore_descriptors
    printf "%s\n" "${bolderror}ERROR:${normal}\\n%s\\n" "$1" >&2
    exit 1
}

select_desktop_environment() {
    debug $DEBUG_INFO "Starting desktop environment selection"
    
    # Create temporary file for dialog output
    temp_choice=$(mktemp)
    debug $DEBUG_DEBUG "Created temporary choice file: $temp_choice"

    # Display dialog menu - using saved descriptors
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
            restore_descriptors
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
                restore_descriptors
                error "Failed to install packages!"
            fi
        ) | dialog --gauge "Installing $DE packages..." 10 70 0 >&3
    else
        debug $DEBUG_ERROR "Package list not found: /install/$PKGLIST"
        restore_descriptors
        error "Package list file not found!"
    fi

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
    
    # Get ZFS pool name from mounted system
    if [[ "$ROOT_FS" == "zfs" ]]; then
        debug $DEBUG_INFO "Getting ZFS pool name from mounted system"
        ZFS_POOL_NAME=$(findmnt -no source / | cut -d/ -f1)
        if [[ -z "$ZFS_POOL_NAME" ]]; then
            debug $DEBUG_ERROR "Failed to detect ZFS pool name"
            error "Could not determine ZFS pool name"
        fi
        debug $DEBUG_INFO "Found ZFS pool name: $ZFS_POOL_NAME"
    fi

    dialog --infobox "Installing and configuring GRUB bootloader..." 5 50 >&3
    (
        echo "10" >&3; sleep 1
        debug $DEBUG_INFO "Installing GRUB packages"
        echo "Installing GRUB and related packages..." >&3
        if ! pacman -S --noconfirm grub os-prober efibootmgr >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to install GRUB packages"
            restore_descriptors
            error "Failed to install GRUB packages!"
        fi
        echo "40" >&3

        debug $DEBUG_INFO "Configuring GRUB defaults for ZFS"
        echo "Configuring GRUB defaults..." >&3
        if [[ "$ROOT_FS" == "zfs" ]]; then
            debug $DEBUG_DEBUG "Setting ZFS root command line in GRUB"
            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"root=ZFS=${ZFS_POOL_NAME}/os/artix quiet\"|" \
                /etc/default/grub >/dev/null 2>&4 || {
                debug $DEBUG_ERROR "Failed to configure GRUB defaults"
                restore_descriptors
                error "Failed to configure GRUB for ZFS!"
            }
        fi
        echo "60" >&3
        
        debug $DEBUG_INFO "Installing GRUB to EFI partition"
        echo "Installing GRUB to EFI system partition..." >&3
        if ! grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --force >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to install GRUB to EFI partition"
            restore_descriptors
            error "Failed to install GRUB!"
        fi
        echo "80" >&3
        
        debug $DEBUG_INFO "Generating GRUB configuration"
        echo "Generating GRUB configuration file..." >&3
        if ! grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to generate GRUB configuration"
            restore_descriptors
            error "Failed to generate GRUB configuration!"
        fi
        echo "100" >&3

        if [[ "$ROOT_FS" == "zfs" ]]; then
            debug $DEBUG_INFO "Enabling ZFS services"
            echo "Enabling ZFS services..." >&3
            mkdir -p /etc/runlevels/boot
            for service in zfs-import zfs-mount zfs-share zfs-zed zfs-load-key; do
                if [[ -f "/etc/init.d/$service" ]]; then
                    ln -sf "/etc/init.d/$service" "/etc/runlevels/boot/$service" || {
                        debug $DEBUG_ERROR "Failed to create symlink for service: $service"
                        restore_descriptors
                        error "Failed to enable ZFS service: $service"
                    }
                    debug $DEBUG_INFO "Enabled $service service"
                else
                    debug $DEBUG_WARN "ZFS service $service not found in /etc/init.d"
                fi
            done
        fi
    ) | dialog --gauge "Installing GRUB bootloader..." 10 70 0 >&3

    dialog --msgbox "GRUB has been installed and configured successfully!" 10 50 >&3
}

regenerate_initcpio() {
    debug $DEBUG_INFO "Regenerating initramfs"
    
    (
        echo "10" >&3; sleep 1
        debug $DEBUG_INFO "Backing up existing initramfs"
        echo "Backing up existing initramfs..." >&3
        if ! cp /boot/initramfs-linux.img /boot/initramfs-linux.img.bak >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to back up existing initramfs"
            restore_descriptors
            error "Failed to back up existing initramfs!"
        fi
        echo "30" >&3
        
        debug $DEBUG_INFO "Regenerating initramfs"
        echo "Regenerating initramfs..." >&3
        if ! mkinitcpio -P >/dev/null 2>&4; then
            debug $DEBUG_ERROR "Failed to regenerate initramfs"
            restore_descriptors
            error "Failed to regenerate initramfs!"
        fi
        echo "100" >&3
        debug $DEBUG_INFO "Initramfs regeneration completed successfully"
    ) | dialog --gauge "Regenerating initramfs..." 10 70 0 >&3

    printf "%s\n" "${bold}Initramfs regenerated successfully!"
}

configure_bootloader() {
    debug $DEBUG_INFO "Configuring bootloader"
    detect_root_filesystem
    install_grub && regenerate_initcpio || {
        error "Error installing GRUB!"
    }
}

addlocales() {
    debug $DEBUG_INFO "Adding locales"
    
    locale_list=$(grep -v '^$' /install/locale.gen | awk '{print $1}' | sort)
    dialog_options=()
    
    while IFS= read -r locale; do
        dialog_options+=("$locale" "$locale")
    done <<< "$locale_list"

    alocale=$(dialog --clear --title "Locale Selection" \
        --menu "Choose your locale from the list:" 20 70 15 "${dialog_options[@]}" 2>&1 1>&3)

    if [[ -z "$alocale" ]]; then
        printf "%s\n" "No locale selected. Skipping locale configuration."
        return 0
    fi

    debug $DEBUG_INFO "Selected locale: $alocale"
    sed -i "s/^#\s*\($alocale\)/\1/" /etc/locale.gen >/dev/null 2>&4
    if ! locale-gen >/dev/null 2>&4; then
        debug $DEBUG_ERROR "Failed to generate locale"
        restore_descriptors
        error "Failed to generate locale!"
    fi

    printf "%s\n" "${bold}Locale '$alocale' has been added and generated successfully!"
}

setlocale() {
    debug $DEBUG_INFO "Setting locale to $alocale"
    
    printf "%s\n" "${bold}Setting locale to $alocale"
    if ! echo "LANG=$alocale" > /etc/locale.conf >/dev/null 2>&4; then
        debug $DEBUG_ERROR "Failed to set locale"
        restore_descriptors
        error "Cannot set locale!"
    fi
}

USERADD() {
    debug $DEBUG_INFO "Creating user account"
    
    username=$(dialog --clear --title "Create User Account" \
        --inputbox "Enter the non-root username:" 10 50 2>&1 1>&3)

    if [[ -z "$username" ]]; then
        debug $DEBUG_ERROR "No username provided"
        restore_descriptors
        error "No username provided!"
    fi

    debug $DEBUG_INFO "Adding user $username"
    if ! useradd -m -G audio,video,wheel "$username" >/dev/null 2>&4; then
        debug $DEBUG_ERROR "Failed to add user $username"
        restore_descriptors
        error "Failed to add user $username"
    fi

    password=$(dialog --clear --title "Set User Password" \
        --passwordbox "Enter the password for $username:" 10 50 2>&1 1>&3)

    if [[ -z "$password" ]]; then
        debug $DEBUG_ERROR "No password provided"
        restore_descriptors
        error "No password provided!"
    fi

    debug $DEBUG_INFO "Setting password for user $username"
    if ! echo "$username:$password" | chpasswd >/dev/null 2>&4; then
        debug $DEBUG_ERROR "Failed to set password for $username"
        restore_descriptors
        error "Failed to set password for $username"
    fi

    printf "%s\n" "${bold}User $username has been created successfully!"
}

passwdroot() {
    debug $DEBUG_INFO "Setting root password"
    
    rootpass=$(dialog --clear --title "Set Root Password" \
        --passwordbox "Enter the password for root:" 10 50 2>&1 1>&3)

    if [[ -z "$rootpass" ]]; then
        debug $DEBUG_ERROR "No root password provided"
        restore_descriptors
        error "No root password provided!"
    fi

    rootpass_confirm=$(dialog --clear --title "Confirm Root Password" \
        --passwordbox "Confirm the password for root:" 10 50 2>&1 1>&3)

    if [[ "$rootpass" != "$rootpass_confirm" ]]; then
        debug $DEBUG_ERROR "Root passwords do not match"
        restore_descriptors
        error "Passwords do not match!"
    fi

    debug $DEBUG_INFO "Setting root password"
    if ! echo "root:$rootpass" | chpasswd >/dev/null 2>&4; then
        debug $DEBUG_ERROR "Failed to set root password"
        restore_descriptors
        error "Failed to set root password"
    fi

    printf "%s\n" "${bold}Root password has been set successfully!"
}

enable_boot_services() {
    debug $DEBUG_INFO "Starting boot services configuration"
    
    local boot_services_file="/install/services/boot-runtime-${DE}.txt"
    debug $DEBUG_DEBUG "Using boot services file: $boot_services_file"

    if [[ ! -f "$boot_services_file" ]]; then
        debug $DEBUG_ERROR "Boot services file not found: $boot_services_file"
        error "Boot services file not found: $boot_services_file"
    fi

    # Ensure boot runlevel directory exists
    mkdir -p /etc/runlevels/boot

    while IFS= read -r service; do
        [[ -z "$service" || "$service" =~ ^# ]] && continue
        
        debug $DEBUG_DEBUG "Processing service: $service"
        if [[ -f "/etc/init.d/$service" ]]; then
            if [[ ! -L "/etc/runlevels/boot/$service" ]]; then
                debug $DEBUG_INFO "Creating symlink for $service in boot runlevel"
                ln -s "/etc/init.d/$service" "/etc/runlevels/boot/$service" || {
                    debug $DEBUG_ERROR "Failed to create symlink for service: $service"
                    error "Failed to enable service: $service in boot"
                }
                debug $DEBUG_INFO "Successfully enabled service: $service"
            else
                debug $DEBUG_DEBUG "Service $service already enabled in boot runlevel"
            fi
        else
            debug $DEBUG_WARN "Service $service does not exist in /etc/init.d, skipping"
        fi
    done < "$boot_services_file"
    
    debug $DEBUG_INFO "Boot services configuration completed"
}

enable_default_services() {
    debug $DEBUG_INFO "Starting default services configuration"
    
    local default_services_file="/install/services/default-runtime-${DE}.txt"
    debug $DEBUG_DEBUG "Using default services file: $default_services_file"

    if [[ ! -f "$default_services_file" ]]; then
        debug $DEBUG_ERROR "Default services file not found: $default_services_file"
        error "Default services file not found: $default_services_file"
    fi

    # Ensure default runlevel directory exists
    mkdir -p /etc/runlevels/default

    while IFS= read -r service; do
        [[ -z "$service" || "$service" =~ ^# ]] && continue
        
        debug $DEBUG_DEBUG "Processing service: $service"
        if [[ -f "/etc/init.d/$service" ]]; then
            if [[ ! -L "/etc/runlevels/default/$service" ]]; then
                debug $DEBUG_INFO "Creating symlink for $service in default runlevel"
                ln -s "/etc/init.d/$service" "/etc/runlevels/default/$service" || {
                    debug $DEBUG_ERROR "Failed to create symlink for service: $service"
                    error "Failed to enable service: $service in default"
                }
                debug $DEBUG_INFO "Successfully enabled service: $service"
            else
                debug $DEBUG_DEBUG "Service $service already enabled in default runlevel"
            fi
        else
            debug $DEBUG_WARN "Service $service does not exist in /etc/init.d, skipping"
        fi
    done < "$default_services_file"
    
    debug $DEBUG_INFO "Default services configuration completed"
}

enableservices() {
    debug $DEBUG_INFO "Starting services configuration for $DE"
    
    printf "%s\n" "${bold}Enabling services for ${DE}"

    (
        echo "5" >&3; sleep 1
        
        debug $DEBUG_INFO "Configuring boot services"
        echo "Enabling boot services..." >&3
        if ! enable_boot_services; then
            restore_descriptors
            error "Failed to enable boot services"
        fi
        echo "40" >&3

        debug $DEBUG_INFO "Configuring default services"
        echo "Enabling default services..." >&3
        if ! enable_default_services; then
            restore_descriptors
            error "Failed to enable default services"
        fi
        echo "70" >&3

        debug $DEBUG_INFO "Verifying service configuration"
        echo "Verifying services..." >&3; sleep 1
        rc-update show > /dev/null || {
            restore_descriptors
            error "Failed to verify services!"
        }
        echo "100" >&3
        debug $DEBUG_INFO "Service configuration completed successfully"
    ) | dialog --gauge "Enabling system services..." 10 70 0 >&3

    printf "%s\n" "${bold}Services enabled successfully!"
}

main() {
    debug $DEBUG_INFO "Starting main installation process"
    
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
}

debug $DEBUG_INFO "Script initialization complete"
main

# Restore original descriptors at end of script
restore_descriptors
exec 3>&- 4>&-