#!/usr/bin/env bash
choose_filesystem() {
    dialog --clear --title "Filesystem Selection" \
        --menu "Choose your preferred filesystem:" 15 50 4 \
        1 "ext4" \
        2 "btrfs" \
        3 "xfs" \
        4 "zfs" 2> /tmp/fs_choice

    FS_CHOICE=$(< /tmp/fs_choice)
    rm /tmp/fs_choice

    case $FS_CHOICE in
        1) FILESYSTEM="ext4" ;;
        2) FILESYSTEM="btrfs" ;;
        3) FILESYSTEM="xfs" ;;
        4) FILESYSTEM="zfs" ;;
        *) error "Invalid choice or no selection made!" ;;
    esac

    dialog --msgbox "You selected $FILESYSTEM as your filesystem." 10 50
}


setup_filesystem() {
    debug $DEBUG_INFO "Setting up filesystem"
    
    case "$FILESYSTEM" in
        ext4)
            debug $DEBUG_DEBUG "Formatting root partition as ext4"
            mkfs.ext4 -F "${DISK}-part2" >> "$LOG_FILE" 2>&1 || error "Failed to format partition as ext4!"
            debug $DEBUG_DEBUG "Mounting root partition"
            mount "${DISK}-part2" $INST_MNT >> "$LOG_FILE" 2>&1 || error "Failed to mount ext4 filesystem!"
            debug $DEBUG_DEBUG "Formatting home partition as ext4"
            mkfs.ext4 -F "${DISK}-part3" >> "$LOG_FILE" 2>&1 || error "Failed to format home partition!"
            debug $DEBUG_DEBUG "Mounting home partition"
            mount --mkdir "${DISK}-part3" $INST_MNT/home >> "$LOG_FILE" 2>&1 || error "Failed to mount home!"
            ;;
        btrfs)
            debug $DEBUG_DEBUG "Formatting root partition as btrfs"
            mkfs.btrfs -f "${DISK}-part2" >> "$LOG_FILE" 2>&1 || error "Failed to format partition as btrfs!"
            debug $DEBUG_DEBUG "Mounting btrfs filesystem"
            mount "${DISK}-part2" $INST_MNT >> "$LOG_FILE" 2>&1 || error "Failed to mount btrfs filesystem!"

            debug $DEBUG_DEBUG "Creating btrfs subvolumes"
            btrfs subvolume create $INST_MNT/@ >> "$LOG_FILE" 2>&1 || error "Failed to create root subvolume!"
            btrfs subvolume create $INST_MNT/@cache >> "$LOG_FILE" 2>&1 || error "Failed to create var subvolume!"
            btrfs subvolume create $INST_MNT/@log >> "$LOG_FILE" 2>&1 || error "Failed to create var log subvolume!"
            
            debug $DEBUG_DEBUG "Formatting home partition as ext4"            
            mkfs.ext4 -F "${DISK}-part3" >> "$LOG_FILE" 2>&1 || error "Failed to format home partition!"

            debug $DEBUG_DEBUG "Remounting with subvolumes"
            umount $INST_MNT >> "$LOG_FILE" 2>&1 || error "Failed to unmount Btrfs filesystem!"
            mount -o subvol=@ "${DISK}-part2" $INST_MNT >> "$LOG_FILE" 2>&1 || error "Failed to mount root subvolume!"
            mkdir -p $INST_MNT/var/cache >> "$LOG_FILE" 2>&1 || error "Failed to create var cache directory!"
            mount -o subvol=@cache "${DISK}-part2" $INST_MNT/var/cache >> "$LOG_FILE" 2>&1 || error "Failed to mount var cache!"
            mkdir -p $INST_MNT/var/log >> "$LOG_FILE" 2>&1 || error "Failed to create var log directory!"
            mount -o subvol=@log "${DISK}-part2" $INST_MNT/var/log >> "$LOG_FILE" 2>&1 || error "Failed to mount var log!"
            mkdir -p $INST_MNT/home >> "$LOG_FILE" 2>&1 || error "Failed to create home directory!"
            mount --mkdir "${DISK}-part3" $INST_MNT/home >> "$LOG_FILE" 2>&1 || error "Failed to mount home!"
            ;;
        xfs)
            debug $DEBUG_DEBUG "Formatting root partition as xfs"
            mkfs.xfs -f "${DISK}-part2" >> "$LOG_FILE" 2>&1 || error "Failed to format partition as xfs!"
            debug $DEBUG_DEBUG "Mounting root partition"
            mount "${DISK}-part2" $INST_MNT >> "$LOG_FILE" 2>&1 || error "Failed to mount xfs filesystem!"
            debug $DEBUG_DEBUG "Formatting home partition as ext4"
            mkfs.ext4 -F "${DISK}-part3" >> "$LOG_FILE" 2>&1 || error "Failed to format home partition!"
            debug $DEBUG_DEBUG "Mounting home partition"
            mount --mkdir "${DISK}-part3" $INST_MNT/home >> "$LOG_FILE" 2>&1 || error "Failed to mount home!"
            ;;
        zfs)
            rootpool || error "Error creating ZFS root pool!"
            createdatasets || error "Error creating ZFS datasets!"
            mountall || error "Error mounting ZFS datasets!"
            ;;
        *)
            debug $DEBUG_ERROR "Invalid filesystem selected: $FILESYSTEM"
            error "Unsupported filesystem selected!"
            ;;
    esac

    debug $DEBUG_INFO "Filesystem setup completed successfully"
}

