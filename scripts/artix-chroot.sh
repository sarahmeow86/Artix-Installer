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

    # Create temporary file for whiptail output
    temp_choice=$(mktemp)
    debug $DEBUG_DEBUG "Created temporary choice file: $temp_choice"

    # Display whiptail menu
    whiptail --clear --backtitle "Artix Installer" --title "Desktop Environment Selection" \
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
        whiptail --backtitle "Artix Installer" --infobox "Installing packages for $DE..." 5 50 >&3
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
        ) | whiptail --backtitle "Artix Installer" --gauge "Installing $DE packages..." 10 70 0 >&3
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

# Function to detect the root filesystem
detect_root_filesystem() {
    ROOT_FS=$(findmnt -n -o FSTYPE /)
    if [[ -z "$ROOT_FS" ]]; then
        error "Failed to detect the root filesystem!"
    fi
    
    # If root is ZFS, get the pool name
    if [[ "$ROOT_FS" == "zfs" ]]; then
        ZFS_POOL_NAME=$(zfs list -H -o name / | cut -d'/' -f1)
        if [[ -z "$ZFS_POOL_NAME" ]]; then
            error "Failed to detect the ZFS pool name!"
        fi
        export ZFS_POOL_NAME
    fi
    
    printf "%s\n" "${bold}Detected root filesystem: $ROOT_FS"
}

# Function to install and configure GRUB
install_grub() {
    exec 3>&1 4>&2
    
    whiptail --backtitle "Artix Installer" --infobox "Installing and configuring GRUB bootloader..." 5 50 >&3
    (
        echo "10" >&3; sleep 1
        echo "Installing GRUB and related packages..." >&3
        pacman -S --noconfirm grub os-prober efibootmgr >/dev/null 2>&4 && echo "50" >&3
        
        echo "Installing GRUB to EFI system partition..." >&3
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB >/dev/null 2>&4 && echo "80" >&3
        
        echo "Generating GRUB configuration file..." >&3
        grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&4 && echo "100" >&3
    ) | whiptail --backtitle "Artix Installer" --gauge "Installing GRUB bootloader..." 10 70 0 >&3

    [[ $? -eq 0 ]] || { exec 1>&3 2>&4; error "Failed to install GRUB!"; }

    whiptail --backtitle "Artix Installer" --msgbox "GRUB has been installed and configured successfully!" 10 50 >&3
    
    exec 1>&3 2>&4 3>&- 4>&-
}

# Function to install and configure ZFSBootMenu
install_zfsbootmenu() {
    exec 3>&1 4>&2
    
    whiptail --backtitle "Artix Installer" --infobox "Installing ZFSBootMenu..." 5 50 >&3
    (
        echo "10" >&3; sleep 1
        echo "Creating ZFSBootMenu directory..." >&3
        mkdir -p /boot/efi/EFI/BOOT >/dev/null 2>&4 && echo "30" >&3

        echo "Downloading ZFSBootMenu EFI file..." >&3
        curl -L https://get.zfsbootmenu.org/efi -o /boot/efi/EFI/BOOT/BOOTX64.EFI >/dev/null 2>&4 && echo "70" >&3

        echo "Configuring EFI boot entry..." >&3
        efibootmgr --disk $(findmnt -n -o SOURCE /boot/efi | sed 's/[0-9]*$//') --part 1 \
            --create --label "ZFSBootMenu" \
            --loader '\EFI\BOOT\BOOTX64.EFI' \
            --unicode "spl_hostid=$(hostid) zbm.timeout=3 zbm.prefer=$ZFS_POOL_NAME zbm.import_policy=hostid" \
            --verbose >/dev/null 2>&4 && echo "100" >&3
    ) | whiptail --backtitle "Artix Installer" --gauge "Installing ZFSBootMenu..." 10 70 0 >&3

    [[ $? -eq 0 ]] || { exec 1>&3 2>&4; error "Failed to install ZFSBootMenu!"; }

    whiptail --backtitle "Artix Installer" --msgbox "ZFSBootMenu has been installed and configured successfully!" 10 50 >&3
    
    exec 1>&3 2>&4 3>&- 4>&-
}

zfsservice() {
    exec 3>&1 4>&2
    
    (
        echo "10" >&3; sleep 1
        echo "Installing ZFS OpenRC package..." >&3
        pacman -U --noconfirm /install/zfs-openrc-20241023-1-any.pkg.tar.zst >/dev/null 2>&4 && echo "30" >&3

        local services=("zfs-import" "zfs-load-key" "zfs-share" "zfs-zed" "zfs-mount")
        local current=40
        local step=10

        for service in "${services[@]}"; do
            echo "Adding $service service to boot..." >&3
            rc-update add "$service" boot >/dev/null 2>&4 && echo "$current" >&3
            ((current += step))
        done
    ) | whiptail --backtitle "Artix Installer" --gauge "Configuring ZFS services..." 10 70 0 >&3

    [[ $? -eq 0 ]] || { exec 1>&3 2>&4; error "Error configuring ZFS services!"; }

    printf "%s\n" "${bold}ZFS services configured successfully!"
    
    exec 1>&3 2>&4 3>&- 4>&-
}

regenerate_initcpio() {
    exec 3>&1 4>&2
    
    (
        echo "10" >&3; sleep 1
        echo "Backing up existing initramfs..." >&3
        cp /boot/initramfs-linux.img /boot/initramfs-linux.img.bak >/dev/null 2>&4 && echo "30" >&3
        
        echo "Regenerating initramfs..." >&3
        mkinitcpio -P >/dev/null 2>&4 && echo "100" >&3
    ) | whiptail --backtitle "Artix Installer" --gauge "Regenerating initramfs..." 10 70 0 >&3

    [[ $? -eq 0 ]] || { exec 1>&3 2>&4; error "Error regenerating initramfs!"; }

    printf "%s\n" "${bold}Initramfs regenerated successfully!"
    
    exec 1>&3 2>&4 3>&- 4>&-
}

configure_bootloader() {
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
    exec 3>&1 4>&2
    
    locale_list=$(grep -v '^$' /install/locale.gen | awk '{print $1}' | sort)
    dialog_options=()
    
    while IFS= read -r locale; do
        dialog_options+=("$locale" "$locale")
    done <<< "$locale_list"

    alocale=$(whiptail --backtitle "Artix Installer" --clear --title "Locale Selection" \
        --menu "Choose your locale from the list:" 20 70 15 "${dialog_options[@]}" 2>&1 1>&3)

    if [[ -z "$alocale" ]]; then
        printf "%s\n" "No locale selected. Skipping locale configuration."
        exec 1>&3 2>&4 3>&- 4>&-
        return 0
    fi

    sed -i "s/^#\s*\($alocale\)/\1/" /etc/locale.gen >/dev/null 2>&4
    locale-gen >/dev/null 2>&4 || {
        exec 1>&3 2>&4
        error "Failed to generate locale!"
    }

    printf "%s\n" "${bold}Locale '$alocale' has been added and generated successfully!"
    
    exec 1>&3 2>&4 3>&- 4>&-
}

setlocale() {
    exec 3>&1 4>&2
    
    printf "%s\n" "${bold}Setting locale to $alocale"
    echo "LANG=$alocale" > /etc/locale.conf >/dev/null 2>&4 || {
        exec 1>&3 2>&4
        error "Cannot set locale!"
    }
    
    exec 1>&3 2>&4 3>&- 4>&-
}

USERADD() {
    exec 3>&1 4>&2
    
    username=$(whiptail --backtitle "Artix Installer" --clear --title "Create User Account" \
        --inputbox "Enter the non-root username:" 10 50 2>&1 1>&3)

    if [[ -z "$username" ]]; then
        exec 1>&3 2>&4
        error "No username provided!"
    fi

    useradd -m -G audio,video,wheel "$username" >/dev/null 2>&4 || {
        exec 1>&3 2>&4
        error "Failed to add user $username"
    }

    password=$(whiptail --backtitle "Artix Installer" --clear --title "Set User Password" \
        --passwordbox "Enter the password for $username:" 10 50 2>&1 1>&3)

    if [[ -z "$password" ]]; then
        exec 1>&3 2>&4
        error "No password provided!"
    fi

    echo "$username:$password" | chpasswd >/dev/null 2>&4 || {
        exec 1>&3 2>&4
        error "Failed to set password for $username"
    }

    printf "%s\n" "${bold}User $username has been created successfully!"
    
    exec 1>&3 2>&4 3>&- 4>&-
}

passwdroot() {
    exec 3>&1 4>&2
    
    rootpass=$(whiptail --backtitle "Artix Installer" --clear --title "Set Root Password" \
        --passwordbox "Enter the password for root:" 10 50 2>&1 1>&3)

    if [[ -z "$rootpass" ]]; then
        exec 1>&3 2>&4
        error "No root password provided!"
    fi

    rootpass_confirm=$(whiptail --backtitle "Artix Installer" --clear --title "Confirm Root Password" \
        --passwordbox "Confirm the password for root:" 10 50 2>&1 1>&3)

    if [[ "$rootpass" != "$rootpass_confirm" ]]; then
        exec 1>&3 2>&4
        error "Passwords do not match!"
    fi

    echo "root:$rootpass" | chpasswd >/dev/null 2>&4 || {
        exec 1>&3 2>&4
        error "Failed to set root password"
    }

    printf "%s\n" "${bold}Root password has been set successfully!"
    
    exec 1>&3 2>&4 3>&- 4>&-
}

enable_boot_services() {
    exec 3>&1 4>&2
    
    local boot_services_file="/install/services/boot-runtime-${DE}.txt"

    if [[ ! -f "$boot_services_file" ]]; then
        exec 1>&3 2>&4
        error "Boot services file not found: $boot_services_file"
    fi

    while IFS= read -r service; do
        [[ -z "$service" || "$service" =~ ^# ]] && continue
        
        if ! rc-service --exists "$service"; then
            continue
        fi

        if rc-update show boot | grep -q "^[[:space:]]*$service\$"; then
            continue
        fi

        if ! rc-update add "$service" boot >/dev/null 2>&4; then
            exec 1>&3 2>&4
            error "Failed to enable service: $service"
        fi
    done < "$boot_services_file"
    
    exec 1>&3 2>&4 3>&- 4>&-
}

enable_default_services() {
    exec 3>&1 4>&2
    
    local default_services_file="/install/services/default-runtime-${DE}.txt"

    if [[ ! -f "$default_services_file" ]]; then
        exec 1>&3 2>&4
        error "Default services file not found: $default_services_file"
    fi

    while IFS= read -r service; do
        [[ -z "$service" || "$service" =~ ^# ]] && continue
        
        if ! rc-service --exists "$service"; then
            continue
        fi

        if rc-update show default | grep -q "^[[:space:]]*$service\$"; then
            continue
        fi

        if ! rc-update add "$service" default >/dev/null 2>&4; then
            exec 1>&3 2>&4
            error "Failed to enable service: $service"
        fi
    done < "$default_services_file"
    
    exec 1>&3 2>&4 3>&- 4>&-
}

enableservices() {
    exec 3>&1 4>&2
    
    printf "%s\n" "${bold}Enabling services for ${DE}"

    # Start the progress bar
    (
        echo "5" >&3; sleep 1
        
        # Enable boot services and show progress
        echo "Enabling boot services..." >&3
        enable_boot_services
        echo "40" >&3

        # Enable default services and show progress
        echo "Enabling default services..." >&3
        enable_default_services
        echo "70" >&3

        # Verify services were enabled correctly
        echo "Verifying services..." >&3; sleep 1
        rc-update show >/dev/null 2>&4 && echo "100" >&3
        
    ) | whiptail --backtitle "Artix Installer" --gauge "Enabling system services..." 10 70 0 >&3

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
    whiptail --backtitle "Artix Installer" --title "Installation Complete" --msgbox "\
${bold}Finish!${normal}\n\n\
The installation process has been completed successfully." 10 50 >&3

    exec 1>&3 2>&4 3>&- 4>&-
}

debug $DEBUG_INFO "Script initialization complete"
main