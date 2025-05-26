#!/usr/bin/env bash
fstab() {
    debug $DEBUG_INFO "Starting fstab generation"
    printf "%s\n" "${bold}Generating fstab"

    # Start the progress bar
    (
        echo "10"; sleep 1
        debug $DEBUG_DEBUG "Creating /etc directory"
        mkdir -p "$INST_MNT/etc" >> "$LOG_FILE" 2>&1 || error "Failed to create /etc directory!"
        
        if [[ $FILESYSTEM == "btrfs" || $FILESYSTEM == "xfs" || $FILESYSTEM == "ext4" ]]; then
            debug $DEBUG_DEBUG "Generating fstab for $FILESYSTEM"
            echo "Generating fstab with UUIDs..."; sleep 1
            fstabgen -U "$INST_MNT" >> "$INST_MNT/etc/fstab" 2>> "$LOG_FILE" && echo "100"
        elif [[ $FILESYSTEM == "zfs" ]]; then
            debug $DEBUG_DEBUG "Generating fstab for ZFS"
            echo "Adding EFI partition to fstab..."; sleep 1
            echo "UUID=$(blkid -s UUID -o value ${DISK}-part1) /boot/efi vfat umask=0022,fmask=0022,dmask=0022 0 1" >> "$INST_MNT/etc/fstab" 2>> "$LOG_FILE" && echo "50"
            
            echo "Adding swap partition to fstab..."; sleep 1
            echo "UUID=$(blkid -s UUID -o value ${DISK}-part3) none swap defaults 0 0" >> "$INST_MNT/etc/fstab" 2>> "$LOG_FILE" && echo "100"
        else
            debug $DEBUG_ERROR "Unsupported filesystem: $FILESYSTEM"
            error "Unsupported filesystem: $FILESYSTEM"
        fi
    ) | dialog --gauge "Generating fstab..." 10 70 0

    # Verify fstab
    debug $DEBUG_DEBUG "Verifying fstab file"
    if [[ ! -f "$INST_MNT/etc/fstab" ]]; then
        debug $DEBUG_ERROR "fstab file not created"
        error "Error generating fstab!"
    fi

    if [[ ! -s "$INST_MNT/etc/fstab" ]]; then
        debug $DEBUG_ERROR "fstab file is empty"
        error "Generated fstab is empty!"
    fi

    debug $DEBUG_INFO "fstab generation completed successfully"
    printf "%s\n" "${bold}fstab generated successfully!"
}

configure_initramfs() {
    debug $DEBUG_INFO "Starting initramfs configuration"
    printf "%s\n" "${bold}Configuring initramfs..."

    (
        echo "10"; sleep 1
        
        if [[ $FILESYSTEM == "zfs" ]]; then
            debug $DEBUG_DEBUG "Configuring for ZFS"
            echo "Backing up existing mkinitcpio.conf..."; sleep 1
            if ! mv $INST_MNT/etc/mkinitcpio.conf $INST_MNT/etc/mkinitcpio.conf.back >> "$LOG_FILE" 2>&1; then
                debug $DEBUG_ERROR "Failed to backup mkinitcpio.conf"
                error "Failed to back up mkinitcpio.conf!"
            else
                echo "30"
            fi
            debug $DEBUG_DEBUG "Writing ZFS-enabled mkinitcpio.conf"
            tee $INST_MNT/etc/mkinitcpio.conf >> "$LOG_FILE" 2>&1 <<EOF
HOOKS=(base udev autodetect modconf block keyboard zfs filesystems)
EOF
            echo "50"
        fi

        debug $DEBUG_DEBUG "Regenerating initramfs"
        echo "Regenerating initramfs..."; sleep 1
        artix-chroot $INST_MNT /bin/bash -c "mkinitcpio -P" >> "$LOG_FILE" 2>&1 && echo "100"
    ) | dialog --gauge "Configuring initramfs..." 10 70 0

    if [[ $? -ne 0 ]]; then
        debug $DEBUG_ERROR "initramfs regeneration failed"
        error "Error regenerating initramfs!"
    fi

    debug $DEBUG_INFO "initramfs configuration completed"
    printf "%s\n" "${bold}Initramfs configuration completed successfully!"
}


finishtouch() {
    debug $DEBUG_INFO "Starting final system configuration"
    printf "%s\n" "${bold}Finalizing base installation"

    # Start the progress bar
    (
        echo "10"; sleep 1

        if [[ -n "$LOCALE" ]]; then
            debug $DEBUG_INFO "Using provided locale: $LOCALE"
            sed -i "s/^#\s*\($LOCALE\)/\1/" $INST_MNT/etc/locale.gen
            echo "LANG=$LOCALE" > $INST_MNT/etc/locale.conf
        else
            echo "Selecting locale..."; sleep 1
            debug $DEBUG_DEBUG "Getting locale list"
            locale_list=$(grep -v '^#' /usr/share/i18n/SUPPORTED | cut -d' ' -f1 | sort -u)
            dialog_options=()
            while IFS= read -r locale; do
                dialog_options+=("$locale" "$locale")
            done <<< "$locale_list"

            alocale=$(dialog --clear --title "Locale Selection" \
                --menu "Choose your locale from the list:" 20 70 15 "${dialog_options[@]}" \
                2>> "$LOG_FILE" 1>/dev/tty)

            if [[ -n "$alocale" ]]; then
                debug $DEBUG_INFO "Setting locale: $alocale"
                sed -i "s/^#\s*\($alocale\)/\1/" $INST_MNT/etc/locale.gen
                echo "LANG=$alocale" > $INST_MNT/etc/locale.conf
            fi
        fi
        echo "30"
        
        echo "Setting timezone..."; sleep 1
        debug $DEBUG_DEBUG "Setting timezone to: $INST_TZ"
        ln -sf $INST_MNT/usr/share/zoneinfo/$INST_TZ $INST_MNT/etc/localtime >> "$LOG_FILE" 2>&1 && echo "70"
        
        debug $DEBUG_DEBUG "Configuring locale settings"
        echo "en_US.UTF-8 UTF-8" >> $INST_MNT/etc/locale.gen 2>> "$LOG_FILE"
        debug $DEBUG_DEBUG "Running locale-gen"
        artix-chroot $INST_MNT /bin/bash -c locale-gen >> "$LOG_FILE" 2>&1 && echo "100"
    ) | dialog --gauge "Finalizing base installation..." 10 70 0

    if [[ $? -ne 0 ]]; then
        debug $DEBUG_ERROR "Failed to complete base system configuration"
        error "Failed to complete base system configuration!"
    fi

    debug $DEBUG_INFO "Base system configuration completed"
    printf "%s\n" "${bold}Base system configuration completed successfully!"
}

prepare_chroot() {
    debug $DEBUG_INFO "Starting chroot environment preparation"
    printf "%s\n" "${bold}Preparing chroot environment"

    # Start the progress bar
    (
        echo "10"; sleep 1
        debug $DEBUG_DEBUG "Creating installation directories"
        mkdir -p $INST_MNT/install >> "$LOG_FILE" 2>&1 || error "Failed to create install directory!"
        
        debug $DEBUG_DEBUG "Copying package lists"
        cp misc/pkglist-*.txt $INST_MNT/install/ >> "$LOG_FILE" 2>&1 || error "Failed to copy package lists!"
        
        debug $DEBUG_DEBUG "Creating services directory"
        mkdir -p $INST_MNT/install/services >> "$LOG_FILE" 2>&1
        debug $DEBUG_DEBUG "Copying service files"
        cp misc/services/* $INST_MNT/install/services/ >> "$LOG_FILE" 2>&1 || error "Failed to copy service files!"

        if [[ $FILESYSTEM == "zfs" ]]; then
            debug $DEBUG_DEBUG "Copying ZFS OpenRC package"
            cp misc/zfs-openrc-20241023-1-any.pkg.tar.zst $INST_MNT/install/ >> "$LOG_FILE" 2>&1 || error "Failed to copy ZFS OpenRC package!"
        fi

        debug $DEBUG_DEBUG "Preparing chroot script with variables"
        awk -v n=5 -v s="DISK=${DISK}" 'NR == n {print s} {print}' scripts/artix-chroot.sh > scripts/artix-chroot-new2.sh 2>> "$LOG_FILE"
        mv scripts/artix-chroot-new2.sh $INST_MNT/install/artix-chroot.sh
        chmod +x $INST_MNT/install/artix-chroot.sh >> "$LOG_FILE" 2>&1 && echo "80"
        
        debug $DEBUG_DEBUG "Chroot environment preparation complete"
        echo "100"
    ) | dialog --gauge "Preparing chroot environment..." 10 70 0

    if [[ $? -ne 0 ]]; then
        debug $DEBUG_ERROR "Failed to prepare chroot environment"
        error "Failed to prepare chroot environment!"
    fi

    debug $DEBUG_INFO "Chroot environment prepared successfully"
    printf "%s\n" "${bold}Chroot environment prepared successfully!"
}

run_chroot() {
    printf "%s\n" "${bold}Running chroot script"
    
    artix-chroot $INST_MNT /bin/bash /install/artix-chroot.sh 
    printf "%s\n" "${bold}Chroot script executed successfully!"
}