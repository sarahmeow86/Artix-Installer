#!/usr/bin/env bash
efiswap() {
    debug $DEBUG_INFO "Setting up EFI and swap partitions"
    # Show progress dialog while setting up partitions
    (
        echo "0"
        echo "Setting up EFI partition..."; sleep 1
        debug $DEBUG_DEBUG "Creating EFI filesystem on ${DISK}-part1"
        mkfs.fat -F 32 "${DISK}-part1" >> "$LOG_FILE" 2>&1 && echo "30"
        debug $DEBUG_DEBUG "Mounting EFI partition"
        mkdir -p ${INST_MNT}/boot/efi >> "$LOG_FILE" 2>&1
        mount "${DISK}-part1" ${INST_MNT}/boot/efi >> "$LOG_FILE" 2>&1 && echo "60"
        
        debug $DEBUG_DEBUG "Setting up swap partition"
        if [[ "$FILESYSTEM" == "zfs" ]]; then
            debug $DEBUG_DEBUG "Setting up swap for ZFS: ${DISK}-part3"
            echo "Creating swap partition..."; sleep 1
            mkswap -L SWAP "${DISK}-part3" >> "$LOG_FILE" 2>&1 && echo "70"
            echo "Activating swap partition..."; sleep 1
            swapon "${DISK}-part3" >> "$LOG_FILE" 2>&1 && echo "100"
        else
            debug $DEBUG_DEBUG "Setting up swap for traditional filesystem: ${DISK}-part4"
            echo "Creating swap partition..."; sleep 1
            mkswap -L SWAP "${DISK}-part4" >> "$LOG_FILE" 2>&1 && echo "70"
            echo "Activating swap partition..."; sleep 1
            swapon "${DISK}-part4" >> "$LOG_FILE" 2>&1 && echo "80"
        fi
    ) | dialog --gauge "Setting up partitions..." 10 70 0

    # Verify mounts
    debug $DEBUG_DEBUG "Verifying partition mounts"
    if ! mountpoint -q "${INST_MNT}/boot/efi"; then
        debug $DEBUG_ERROR "EFI partition not mounted"
        error "Failed to mount EFI partition!"
    fi

    debug $DEBUG_INFO "EFI and swap setup completed successfully"
}