#!/usr/bin/env bash

bold=$(tput setaf 2 bold)      # makes text bold and sets color to 2
bolderror=$(tput setaf 3 bold) # makes text bold and sets color to 3
normal=$(tput sgr0)            # resets text settings back to normal

error() {
    printf "%s\n" "${bolderror}ERROR:${normal}\\n%s\\n" "$1" >&2
    exit 1
}

select_desktop_environment() {
    # Save original stdout and stderr
    exec 3>&1
    exec 4>&2
    
    # Create temporary file for dialog output
    temp_choice=$(mktemp)

    # Display whiptail menu
    whiptail --clear --backtitle "Artix Installer" --title "Desktop Environment Selection" \
        --menu "Choose a desktop environment to install:" 15 60 6 \
        1 "Base (No Desktop Environment)" \
        2 "Cinnamon" \
        3 "MATE" \
        4 "KDE Plasma" \
        5 "LXQt" \
        6 "XFCE" 2>"$temp_choice"

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
            error "Invalid choice or no selection made!"
            ;;
    esac

    # Install packages from the selected pkglist
    if [[ -f "/install/$PKGLIST" ]]; then
        whiptail --backtitle "Artix Installer" --infobox "Installing packages for $DE..." 5 50
        (
            echo "10" ; sleep 1
            echo "Installing packages..."
            if pacman -Sy --noconfirm - < "/install/$PKGLIST" 2>/dev/null; then
                echo "100"
            else
                error "Failed to install packages!"
            fi
        ) | whiptail --backtitle "Artix Installer" --gauge "Installing $DE packages..." 10 70 0
    else
        error "Package list file not found!"
    fi

    # Restore original stdout and stderr
    exec 1>&3
    exec 2>&4
    exec 3>&-
    exec 4>&-

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
    whiptail --backtitle "Artix Installer" --infobox "Installing and configuring GRUB bootloader..." 5 50
    (
        echo "10" ; sleep 1
        echo "Installing GRUB and related packages..." ; sleep 1
        pacman -S --noconfirm grub os-prober efibootmgr 2>/dev/null || error "Failed to install GRUB packages!" && echo "50"
        
        echo "Installing GRUB to EFI system partition..." ; sleep 1
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB 2>/dev/null || error "Failed to install GRUB!" && echo "80"
        
        echo "Generating GRUB configuration file..." ; sleep 1
        grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || error "Failed to generate GRUB configuration!" && echo "100"
    ) | whiptail --backtitle "Artix Installer" --gauge "Installing GRUB bootloader..." 10 70 0

    whiptail --backtitle "Artix Installer" --msgbox "GRUB has been installed and configured successfully!" 10 50
}

# Function to install and configure ZFSBootMenu
install_zfsbootmenu() {
    # Save original stdout and stderr
    exec 3>&1
    exec 4>&2
    
    whiptail --backtitle "Artix Installer" --infobox "Installing ZFSBootMenu..." 5 50
    (
        echo "10" ; sleep 1
        echo "Creating ZFSBootMenu directory..." ; sleep 1
        mkdir -p /boot/efi/EFI/BOOT 2>/dev/null && echo "30"

        echo "Downloading ZFSBootMenu EFI file..." ; sleep 1
        curl -L https://get.zfsbootmenu.org/efi -o /boot/efi/EFI/BOOT/BOOTX64.EFI 2>/dev/null && echo "70"

        echo "Configuring EFI boot entry..." ; sleep 1
        efibootmgr --disk $(findmnt -n -o SOURCE /boot/efi | sed 's/[0-9]*$//') --part 1 \
            --create --label "ZFSBootMenu" \
            --loader '\EFI\BOOT\BOOTX64.EFI' \
            --unicode "spl_hostid=$(hostid) zbm.timeout=3 zbm.prefer=$ZFS_POOL_NAME zbm.import_policy=hostid" \
            --verbose 2>/dev/null && echo "100"
    ) | whiptail --backtitle "Artix Installer" --gauge "Installing ZFSBootMenu..." 10 70 0

    if [[ $? -ne 0 ]]; then
        error "Failed to install ZFSBootMenu!"
    fi

    whiptail --backtitle "Artix Installer" --msgbox "ZFSBootMenu has been installed and configured successfully!" 10 50

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
    
    # Start the progress bar
    (
        echo "10" ; sleep 1
        echo "Installing ZFS OpenRC package..." ; sleep 1
        pacman -U --noconfirm /install/zfs-openrc-20241023-1-any.pkg.tar.zst 2>/dev/null && echo "30"

        local services=("zfs-import" "zfs-load-key" "zfs-share" "zfs-zed" "zfs-mount")
        local current=40
        local step=10

        for service in "${services[@]}"; do
            echo "Adding $service service to boot..." ; sleep 1
            rc-update add "$service" boot 2>/dev/null && echo "$current"
            ((current += step))
        done
    ) | whiptail --backtitle "Artix Installer" --gauge "Configuring ZFS services..." 10 70 0

    if [[ $? -ne 0 ]]; then
        error "Error configuring ZFS services!"
    fi

    printf "%s\n" "${bold}ZFS services configured successfully!"

    # Restore original stdout and stderr
    exec 1>&3
    exec 2>&4
    exec 3>&-
    exec 4>&-
}

regenerate_initcpio() {
    # Save original stdout and stderr
    exec 3>&1
    exec 4>&2
    
    # Start the progress bar
    (
        echo "10" ; sleep 1
        echo "Backing up existing initramfs..." ; sleep 1
        cp /boot/initramfs-linux.img /boot/initramfs-linux.img.bak 2>/dev/null && echo "30"
        
        echo "Regenerating initramfs..." ; sleep 1
        mkinitcpio -P 2>/dev/null && echo "100"
    ) | whiptail --backtitle "Artix Installer" --gauge "Regenerating initramfs..." 10 70 0

    if [[ $? -ne 0 ]]; then
        error "Error regenerating initramfs!"
    fi

    printf "%s\n" "${bold}Initramfs regenerated successfully!"

    # Restore original stdout and stderr
    exec 1>&3
    exec 2>&4
    exec 3>&-
    exec 4>&-
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
    locale_list=$(grep -v '^$' /install/locale.gen | awk '{print $1}' | sort)
    dialog_options=()
    
    while IFS= read -r locale; do
        dialog_options+=("$locale" "$locale")
    done <<< "$locale_list"

    alocale=$(whiptail --backtitle "Artix Installer" --clear --title "Locale Selection" \
        --menu "Choose your locale from the list:" 20 70 15 "${dialog_options[@]}" 3>&1 1>&2 2>&3)

    if [[ -z "$alocale" ]]; then
        printf "%s\n" "No locale selected. Skipping locale configuration."
        return 0
    fi

    sed -i "s/^#\s*\($alocale\)/\1/" /etc/locale.gen 2>/dev/null
    locale-gen 2>/dev/null || {
        error "Failed to generate locale!"
    }

    printf "%s\n" "${bold}Locale '$alocale' has been added and generated successfully!"
}

setlocale() {
    printf "%s\n" "${bold}Setting locale to $alocale"
    echo "LANG=$alocale" > /etc/locale.conf || {
        error "Cannot set locale!"
    }
}

USERADD() {
    username=$(whiptail --backtitle "Artix Installer" --clear --title "Create User Account" \
        --inputbox "Enter the non-root username:" 10 50 3>&1 1>&2 2>&3)

    if [[ -z "$username" ]]; then
        error "No username provided!"
    fi

    useradd -m -G audio,video,wheel "$username" 2>/dev/null || {
        error "Failed to add user $username"
    }

    password=$(whiptail --backtitle "Artix Installer" --clear --title "Set User Password" \
        --passwordbox "Enter the password for $username:" 10 50 3>&1 1>&2 2>&3)

    if [[ -z "$password" ]]; then
        error "No password provided!"
    fi

    echo "$username:$password" | chpasswd 2>/dev/null || {
        error "Failed to set password for $username"
    }

    printf "%s\n" "${bold}User $username has been created successfully!"
}

passwdroot() {
    rootpass=$(whiptail --backtitle "Artix Installer" --clear --title "Set Root Password" \
        --passwordbox "Enter the password for root:" 10 50 3>&1 1>&2 2>&3)

    if [[ -z "$rootpass" ]]; then
        error "No root password provided!"
    fi

    rootpass_confirm=$(whiptail --backtitle "Artix Installer" --clear --title "Confirm Root Password" \
        --passwordbox "Confirm the password for root:" 10 50 3>&1 1>&2 2>&3)

    if [[ "$rootpass" != "$rootpass_confirm" ]]; then
        error "Passwords do not match!"
    fi

    echo "root:$rootpass" | chpasswd 2>/dev/null || {
        error "Failed to set root password"
    }

    printf "%s\n" "${bold}Root password has been set successfully!"
}

enable_boot_services() {
    local boot_services_file="/install/services/boot-runtime-${DE}.txt"

    if [[ ! -f "$boot_services_file" ]]; then
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

        if ! rc-update add "$service" boot 2>/dev/null; then
            error "Failed to enable service: $service"
        fi
    done < "$boot_services_file"
}

enable_default_services() {
    local default_services_file="/install/services/default-runtime-${DE}.txt"

    if [[ ! -f "$default_services_file" ]]; then
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

        if ! rc-update add "$service" default 2>/dev/null; then
            error "Failed to enable service: $service"
        fi
    done < "$default_services_file"
}

enableservices() {
    # Save original stdout and stderr
    exec 3>&1
    exec 4>&2

    printf "%s\n" "${bold}Enabling services for ${DE}"

    # Start the progress bar
    (
        echo "5" ; sleep 1
        
        # Enable boot services and show progress
        echo "Enabling boot services..."
        enable_boot_services
        echo "40"

        # Enable default services and show progress
        echo "Enabling default services..."
        enable_default_services
        echo "70"

        # Verify services were enabled correctly
        echo "Verifying services..." ; sleep 1
        rc-update show 2>/dev/null && echo "100"
        
    ) | whiptail --backtitle "Artix Installer" --gauge "Enabling system services..." 10 70 0

    printf "%s\n" "${bold}Services enabled successfully!"

    # Restore original stdout and stderr
    exec 1>&3
    exec 2>&4
    exec 3>&-
    exec 4>&-
}

main() {
    # Save original stdout and stderr
    exec 3>&1
    exec 4>&2

    select_desktop_environment || error "Error selecting desktop environment!"
    addlocales || error "Cannot generate locales"
    setlocale || error "Cannot set locale"
    USERADD || error "Error adding user to your install"
    passwdroot || error "Error setting root password!"
    enableservices || error "Error enabling services!"
    configure_bootloader || error "Error configuring bootloader!"

    # Display completion message
    whiptail --backtitle "Artix Installer" --title "Installation Complete" --msgbox "\
${bold}Finish!${normal}\n\n\
The installation process has been completed successfully." 10 50

    # Restore original stdout and stderr
    exec 1>&3
    exec 2>&4
    exec 3>&-
    exec 4>&-
}

main