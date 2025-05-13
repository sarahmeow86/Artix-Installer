#!/usr/bin/env bash
rootpool() {
    debug $DEBUG_INFO "Starting ZFS root pool creation"
    printf "%s\n" "${bold}Creating root pool"
    dialog --infobox "Starting install, it will take time, so go GRUB a cup of coffee! ;D" 5 50
    sleep 3

    debug $DEBUG_DEBUG "Using disk: $DISK"
    debug $DEBUG_DEBUG "Creating ZFS root pool on: ${DISK}-part2"
    debug $DEBUG_DEBUG "Using pool name: $ZFS_POOL_NAME"

    # Start the progress bar
    (
        echo "10"; sleep 1
        echo "Creating ZFS root pool..."; sleep 1
        zgenhostid -f
        debug $DEBUG_DEBUG "Running zpool create command"
        zpool create -f -o ashift=12 -o autotrim=on \
            -O acltype=posixacl -O xattr=sa -O relatime=on -O compression=lz4 -m none \
            -R $INST_MNT "$ZFS_POOL_NAME" "${DISK}-part2" >> "$LOG_FILE" 2>&1 && echo "50"
        
        debug $DEBUG_DEBUG "ZFS pool creation completed"
        sleep 1
        echo "Finalizing setup..."; sleep 1
        echo "100"
    ) | dialog --gauge "Setting up the ZFS root pool..." 10 70 0

    # Check if the pool was created successfully
    if ! zpool status "$ZFS_POOL_NAME" >> "$LOG_FILE" 2>&1; then
        debug $DEBUG_ERROR "Failed to create ZFS root pool"
        error "Error setting up the root pool!"
    fi

    debug $DEBUG_INFO "Root pool created successfully"
    printf "%s\n" "${bold}Root pool created successfully!"
}

createdatasets() {
    debug $DEBUG_INFO "Starting ZFS dataset creation"
    printf "%s\n" "${bold}Creating root and home datasets"

    # Start the progress bar
    (
        echo "10"; sleep 1
        echo "Creating os dataset..."; sleep 1
        debug $DEBUG_DEBUG "Creating os dataset structure"
        zfs create -o mountpoint=none "$ZFS_POOL_NAME/os" >> "$LOG_FILE" 2>&1 && echo "30"
        
        echo "Creating root filesystem..."; sleep 1
        debug $DEBUG_DEBUG "Creating root filesystem dataset"
        zfs create -o mountpoint=/ -o canmount=noauto "$ZFS_POOL_NAME/os/artix" >> "$LOG_FILE" 2>&1 && echo "60"
        
        echo "Creating home dataset..."; sleep 1
        debug $DEBUG_DEBUG "Creating home dataset"
        zfs create -o mountpoint=/home "$ZFS_POOL_NAME/home" >> "$LOG_FILE" 2>&1 && echo "100"
    ) | dialog --gauge "Creating ZFS datasets..." 10 70 0

    # Verify datasets
    debug $DEBUG_DEBUG "Verifying created datasets"
    if ! zfs list "$ZFS_POOL_NAME/os/artix" >> "$LOG_FILE" 2>&1 || 
       ! zfs list "$ZFS_POOL_NAME/home" >> "$LOG_FILE" 2>&1; then
        debug $DEBUG_ERROR "Failed to create ZFS datasets"
        error "Error creating the datasets!"
    fi

    # Set properties for the datasets
    debug $DEBUG_DEBUG "Setting properties for zfsbootmenu"
    zfs set org.zfsbootmenu:bootfs="$ZFS_POOL_NAME/os/artix" "$ZFS_POOL_NAME" >> "$LOG_FILE" 2>&1 || error "Failed to set bootfs property!"    

    debug $DEBUG_INFO "Datasets created successfully"
    printf "%s\n" "${bold}Datasets created successfully!"
}

mountall() {
    debug $DEBUG_INFO "Starting ZFS dataset mounting"
    printf "%s\n" "${bold}Mounting datasets"

    # Start the progress bar
    (
        echo "10"; sleep 1
        echo "Mounting root dataset..."; sleep 1
        debug $DEBUG_DEBUG "Mounting root dataset"
        zfs mount "$ZFS_POOL_NAME/os/artix" >> "$LOG_FILE" 2>&1 && echo "50"
        
        echo "Mounting home dataset..."; sleep 1
        debug $DEBUG_DEBUG "Mounting home dataset"
        zfs mount "$ZFS_POOL_NAME/home" >> "$LOG_FILE" 2>&1 && echo "100"
    ) | dialog --gauge "Mounting ZFS datasets..." 10 70 0

    # Verify mounts
    debug $DEBUG_DEBUG "Verifying dataset mounts"
    if ! zfs mount | grep -q "$ZFS_POOL_NAME/os/artix" || 
       ! zfs mount | grep -q "$ZFS_POOL_NAME/home"; then
        debug $DEBUG_ERROR "Failed to mount ZFS datasets"
        error "Error mounting datasets!"
    fi

    # Setting cachefile and zgenhostid files
    debug $DEBUG_DEBUG "Setting cachefile and zgenhostid files"
    zpool set cachefile=/etc/zfs/zpool.cache "$ZFS_POOL_NAME" >> "$LOG_FILE" 2>&1 || error "Failed to set cachefile property!"
    zfs set org.zfsbootmenu:commandline="quiet loglevel=4" "$ZFS_POOL_NAME" >> "$LOG_FILE" 2>&1 || error "Failed to set commandline property!"
    mkdir -p "$INST_MNT/etc/zfs" >> "$LOG_FILE" 2>&1 || error "Failed to create /etc/zfs directory!"
    cp /etc/zfs/zpool.cache "$INST_MNT/etc/zfs/zpool.cache" >> "$LOG_FILE" 2>&1 || error "Failed to copy zpool.cache file!"
    cp /etc/hostid "$INST_MNT/etc/hostid" >> "$LOG_FILE" 2>&1 || error "Failed to copy hostid file!"


    debug $DEBUG_INFO "All datasets mounted successfully"
    printf "%s\n" "${bold}All datasets mounted successfully!"
}