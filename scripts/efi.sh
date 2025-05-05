#!/usr/bin/env bash
efiswap() {
    debug $DEBUG_INFO "Starting EFI and swap setup"
    printf "%s\n" "${bold}Formatting and mounting partitions"

    # Start the progress bar
    (
        echo "10"; sleep 1
        
        # Format and mount EFI partition
        echo "Formatting EFI partition..."; sleep 1
        debug $DEBUG_DEBUG "Formatting EFI partition: ${DISK}-part1"
        mkfs.vfat -n EFI ${DISK}-part1 >> "$LOG_FILE" 2>&1 && echo "30"
        
        echo "Mounting EFI partition..."; sleep 1
        debug $DEBUG_DEBUG "Creating EFI mount point and mounting"
        mkdir -p $INST_MNT/boot/efi >> "$LOG_FILE" 2>&1
        mount -t vfat ${DISK}-part1 $INST_MNT/boot/efi >> "$LOG_FILE" 2>&1 && echo "50"

        # Handle swap based on filesystem type
        if [[ "$FILESYSTEM" == "zfs" ]]; then
            debug $DEBUG_DEBUG "Setting up swap for ZFS: ${DISK}-part3"
            echo "Creating swap partition..."; sleep 1
            mkswap -L SWAP ${DISK}-part3 >> "$LOG_FILE" 2>&1 && echo "70"
            echo "Activating swap partition..."; sleep 1
            swapon ${DISK}-part3 >> "$LOG_FILE" 2>&1 && echo "100"
        else
            debug $DEBUG_DEBUG "Setting up swap for traditional filesystem: ${DISK}-part4"
            echo "Creating swap partition..."; sleep 1
            mkswap -L SWAP ${DISK}-part4 >> "$LOG_FILE" 2>&1 && echo "70"
            echo "Activating swap partition..."; sleep 1
            swapon ${DISK}-part4 >> "$LOG_FILE" 2>&1 && echo "80"
        fi
    ) | dialog --gauge "Setting up partitions..." 10 70 0

    # Verify mounts
    debug $DEBUG_DEBUG "Verifying partition mounts"
    if ! mount | grep -q "$INST_MNT/boot/efi"; then
        debug $DEBUG_ERROR "EFI partition mount verification failed"
        error "EFI partition is not mounted!"
    fi

    if [[ "$FILESYSTEM" != "zfs" ]]; then
        if ! mount | grep -q "$INST_MNT/home"; then
            debug $DEBUG_ERROR "Home partition mount verification failed"
            error "Home partition is not mounted!"
        fi
    fi

    debug $DEBUG_INFO "EFI and swap setup completed successfully"
    printf "%s\n" "${bold}Partitions set up successfully!"
}