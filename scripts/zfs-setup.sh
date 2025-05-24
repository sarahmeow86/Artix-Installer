#!/usr/bin/env bash

check_existing_pools() {
    debug $DEBUG_INFO "Checking for existing ZFS pools"
    
    # Get list of importable pools
    local discovered_pools=$(zpool import | grep "pool:" | cut -d: -f2 | tr -d ' ')
    
    if [[ -n "$discovered_pools" ]]; then
        debug $DEBUG_DEBUG "Found existing pools: $discovered_pools"
        if dialog --title "Existing ZFS Pools" \
            --yesno "Found existing ZFS pools:\n\n$discovered_pools\n\nDo you want to import them into the new system?" 12 60; then
            
            debug $DEBUG_INFO "User chose to import existing pools"
            for pool in $discovered_pools; do
                [[ "$pool" == "$ZFS_POOL_NAME" ]] && continue
                debug $DEBUG_DEBUG "Importing pool: $pool to $INST_MNT"
                if ! zpool import -R "$INST_MNT" -N "$pool" >> "$LOG_FILE" 2>&1; then
                    debug $DEBUG_ERROR "Failed to import pool: $pool"
                    error "Failed to import pool: $pool"
                fi
                debug $DEBUG_DEBUG "Mounting datasets for pool: $pool"
                if ! zfs mount -a -l >> "$LOG_FILE" 2>&1; then
                    debug $DEBUG_ERROR "Failed to mount datasets for pool: $pool"
                    error "Failed to mount datasets for pool: $pool"
                fi
                debug $DEBUG_INFO "Successfully imported and mounted pool: $pool"
            done
        else
            debug $DEBUG_INFO "User chose not to import existing pools"
        fi
    else
        debug $DEBUG_DEBUG "No existing pools found"
    fi
}

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
        zpool create -f -o ashift=12 -o autotrim=on -o compatibility=openzfs-2.1-linux \
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

    # Check for other pools to import after root pool is set up
    check_existing_pools

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
    debug $DEBUG_INFO "Datasets created successfully"
    printf "%s\n" "${bold}Datasets created successfully!"
}

mountall() {
    debug $DEBUG_INFO "Starting ZFS dataset mounting"
    printf "%s\n" "${bold}Mounting datasets"

    # Start the progress bar
    (
        echo "10"; sleep 1
        echo "Exporting ZFS pool..."; sleep 1
        debug $DEBUG_DEBUG "Exporting pool: $ZFS_POOL_NAME"
        zpool export "$ZFS_POOL_NAME" >> "$LOG_FILE" 2>&1 && echo "20"

        echo "Importing ZFS pool..."; sleep 1
        debug $DEBUG_DEBUG "Importing pool with -N flag: $ZFS_POOL_NAME"
        zpool import -N "$ZFS_POOL_NAME" >> "$LOG_FILE" 2>&1 && echo "30"

        echo "Mounting root dataset..."; sleep 1
        debug $DEBUG_DEBUG "Mounting root dataset"
        zfs mount "$ZFS_POOL_NAME/os/artix" >> "$LOG_FILE" 2>&1 && echo "60"
        
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
    mkdir -p "$INST_MNT/etc/zfs" >> "$LOG_FILE" 2>&1 || error "Failed to create /etc/zfs directory!"
    cp /etc/zfs/zpool.cache "$INST_MNT/etc/zfs/zpool.cache" >> "$LOG_FILE" 2>&1 || error "Failed to copy zpool.cache file!"
    cp /etc/hostid "$INST_MNT/etc/hostid" >> "$LOG_FILE" 2>&1 || error "Failed to copy hostid file!"


    debug $DEBUG_INFO "All datasets mounted successfully"
    printf "%s\n" "${bold}All datasets mounted successfully!"
}