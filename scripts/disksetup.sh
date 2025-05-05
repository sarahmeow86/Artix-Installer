#!/usr/bin/env bash

get_disk_size() {
    local disk=$1
    debug $DEBUG_DEBUG "Getting disk size for: /dev/disk/by-id/$disk"
    local size=$(lsblk -b -n -d -o SIZE "/dev/disk/by-id/$disk")
    local size_gb=$(( size / 1024 / 1024 / 1024 ))
    debug $DEBUG_DEBUG "Disk size: ${size_gb}GB"
    echo $size_gb
}

partdrive() {
    debug $DEBUG_INFO "Starting disk partitioning"
    printf "%s\n" "${bold}Partitioning drive"

    # Get total disk size in GB
    debug $DEBUG_DEBUG "Calculating disk size"
    DISK_SIZE=$(get_disk_size "$disk")
    
    # Calculate recommended swap size based on system RAM
    debug $DEBUG_DEBUG "Calculating swap size"
    RAM_SIZE=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
    if [ $RAM_SIZE -le 2 ]; then
        RECOMMENDED_SWAP=$(( RAM_SIZE * 2 ))
    elif [ $RAM_SIZE -le 8 ]; then
        RECOMMENDED_SWAP=$RAM_SIZE
    else
        RECOMMENDED_SWAP=$RAM_SIZE
    fi
    debug $DEBUG_DEBUG "RAM: ${RAM_SIZE}GB, Recommended swap: ${RECOMMENDED_SWAP}GB"

    # Prompt for swap size with recommended value
    while true; do
        debug $DEBUG_DEBUG "Prompting for swap size"
        SWAP_SIZE=$(dialog --clear --title "Swap Partition Size" \
            --inputbox "Enter the size of the swap partition in GB\nRecommended size: ${RECOMMENDED_SWAP}GB\nAvailable disk space: ${DISK_SIZE}GB" \
            12 60 "$RECOMMENDED_SWAP" 3>&1 1>&2 2>&3)
    
        if [[ -n "$SWAP_SIZE" && "$SWAP_SIZE" =~ ^[0-9]+$ && "$SWAP_SIZE" -lt "$DISK_SIZE" ]]; then
            debug $DEBUG_INFO "User selected swap size: ${SWAP_SIZE}GB"
            break
        else
            debug $DEBUG_WARN "Invalid swap size entered"
            dialog --title "Invalid Input" --msgbox "Invalid swap size! Please enter a positive integer less than ${DISK_SIZE}." 10 50
        fi
    done

    # Calculate remaining space after EFI (1GB) and swap
    REMAINING_SPACE=$(( DISK_SIZE - SWAP_SIZE - 1 ))
    debug $DEBUG_DEBUG "Remaining space after EFI and swap: ${REMAINING_SPACE}GB"

    # Start partitioning
    (
        echo "10"; sleep 1
        debug $DEBUG_DEBUG "Wiping disk: /dev/disk/by-id/$disk"
        echo "Wiping disk..."; sleep 1
        sgdisk --zap-all "/dev/disk/by-id/$disk" >> "$LOG_FILE" 2>&1 && echo "20"

        debug $DEBUG_DEBUG "Creating EFI partition (1GB)"
        echo "Creating EFI partition..."; sleep 1
        sgdisk -n1:0:+1G -t1:EF00 "/dev/disk/by-id/$disk" >> "$LOG_FILE" 2>&1 && echo "40"

        if [[ "$FILESYSTEM" == "zfs" ]]; then
            debug $DEBUG_DEBUG "Creating ZFS partition"
            echo "Creating ZFS partition..."; sleep 1
            sgdisk -n2:0:-${SWAP_SIZE}G -t2:BF00 "/dev/disk/by-id/$disk" >> "$LOG_FILE" 2>&1 && echo "60"
        else
            # Calculate root partition size (40% of remaining space)
            ROOT_SIZE=$(( REMAINING_SPACE * 40 / 100 ))
            debug $DEBUG_DEBUG "Creating root partition (${ROOT_SIZE}GB)"
            echo "Creating root partition..."; sleep 1
            sgdisk -n2:0:+${ROOT_SIZE}G -t2:8300 "/dev/disk/by-id/$disk" >> "$LOG_FILE" 2>&1 && echo "60"
            
            debug $DEBUG_DEBUG "Creating home partition"
            echo "Creating home partition..."; sleep 1
            sgdisk -n3:0:-${SWAP_SIZE}G -t3:8300 "/dev/disk/by-id/$disk" >> "$LOG_FILE" 2>&1 && echo "80"
        fi

        debug $DEBUG_DEBUG "Creating swap partition (${SWAP_SIZE}GB)"
        echo "Creating swap partition..."; sleep 1
        if [[ "$FILESYSTEM" == "zfs" ]]; then
            sgdisk -n3:0:0 -t3:8308 "/dev/disk/by-id/$disk" >> "$LOG_FILE" 2>&1 && echo "90"
        else
            sgdisk -n4:0:0 -t4:8308 "/dev/disk/by-id/$disk" >> "$LOG_FILE" 2>&1 && echo "90"
        fi

        debug $DEBUG_DEBUG "Running partprobe"
        partprobe >> "$LOG_FILE" 2>&1 && echo "100"
    ) | dialog --gauge "Partitioning drive..." 10 70 0

    if [[ $? -ne 0 ]]; then
        debug $DEBUG_ERROR "Partitioning failed"
        error "Failed to partition drive!"
    fi

    debug $DEBUG_INFO "Partitioning completed successfully"
    printf "%s\n" "${bold}Partitioning completed successfully!"
}