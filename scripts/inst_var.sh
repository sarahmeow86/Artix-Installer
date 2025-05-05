#!/usr/bin/env bash
installtz() {
    debug $DEBUG_INFO "Starting timezone configuration"
    printf "%s\n" "${bold}## Setting install variables"

    debug $DEBUG_DEBUG "Generating region list"
    region_list=$(find /usr/share/zoneinfo -mindepth 1 -maxdepth 1 -type d | sed 's|/usr/share/zoneinfo/||' | sort)

    # Prepare the list of regions for the dialog menu
    dialog_options=()
    index=1
    while IFS= read -r region; do
        dialog_options+=("$index" "$region")
        index=$((index + 1))
    done <<< "$region_list"

    # Create a dialog menu for regions
    region_index=$(dialog --clear --title "Region Selection" \
        --menu "Choose your region:" 20 60 15 "${dialog_options[@]}" 3>&1 1>&2 2>&3)

    # Check if the user selected a region
    if [[ -z "$region_index" ]]; then
        error "No region selected!"
    fi

    # Map the selected index back to the region
    region=$(echo "$region_list" | sed -n "${region_index}p")

    debug $DEBUG_DEBUG "Selected region: $region"
    debug $DEBUG_DEBUG "Generating city list for region: $region"
    city_list=$(find "/usr/share/zoneinfo/$region" -type f | sed "s|/usr/share/zoneinfo/$region/||" | sort)

    # Prepare the list of cities for the dialog menu
    dialog_options=()
    index=1
    while IFS= read -r city; do
        dialog_options+=("$index" "$city")
        index=$((index + 1))
    done <<< "$city_list"

    # Create a dialog menu for cities
    city_index=$(dialog --clear --title "City Selection" \
        --menu "Choose your city in $region:" 20 60 15 "${dialog_options[@]}" 3>&1 1>&2 2>&3)

    # Check if the user selected a city
    if [[ -z "$city_index" ]]; then
        error "No city selected!"
    fi

    # Map the selected index back to the city
    city=$(echo "$city_list" | sed -n "${city_index}p")

    INST_TZ="/usr/share/zoneinfo/$region/$city"
    debug $DEBUG_INFO "Timezone set to: $region/$city"
    printf "%s\n" "${bold}Timezone set to $region/$city"
}

installhost() {
    debug $DEBUG_INFO "Starting hostname configuration"
    printf "%s\n" "${bold}## Set desired hostname"

    INST_HOST=$(dialog --clear --title "Hostname Configuration" \
        --inputbox "Enter your desired hostname:" 10 50 3>&1 1>&2 2>&3)

    if [[ -z "$INST_HOST" ]]; then
        debug $DEBUG_ERROR "No hostname provided"
        error "No hostname provided!"
    fi

    debug $DEBUG_INFO "Hostname set to: $INST_HOST"
    printf "%s\n" "${bold}Hostname set to $INST_HOST"
}

installkrn() {
    debug $DEBUG_INFO "Starting kernel selection"
    printf "%s\n" "${bold}Select the kernel you want to install"
    
    kernel_choice=$(dialog --clear --title "Kernel Selection" \
        --menu "Choose one of the following kernels:" 15 50 3 \
        1 "linux" \
        2 "linux-zen" \
        3 "linux-lts" \
        3>&1 1>&2 2>&3)

    case $kernel_choice in
        1) INST_LINVAR="linux" ;;
        2) INST_LINVAR="linux-zen" ;;
        3) INST_LINVAR="linux-lts" ;;
        *) 
            debug $DEBUG_ERROR "Invalid kernel choice selected"
            error "Invalid kernel choice!" 
            ;;
    esac

    debug $DEBUG_INFO "Kernel selected: $INST_LINVAR"
    printf "%s\n" "${bold}Kernel selected: $INST_LINVAR"
}

selectdisk() {
    debug $DEBUG_INFO "Starting disk selection"
    printf "%s\n" "${bold}## Decide which disk you want to use"

    debug $DEBUG_DEBUG "Generating disk list"
    disk_list=$(ls -1 /dev/disk/by-id)

	# Prepare the list for the dialog menu
    dialog_options=()
    for disk in $disk_list; do
        dialog_options+=("$disk" "Disk")
    done

    # Create a dialog menu for disk selection with a larger box
    disk=$(dialog --clear --title "Disk Selection" \
        --menu "Choose a disk to use: DON'T USE PARTITIONS, THIS SCRIPT ASSUMES THE USE OF ONE DRIVE!!" 30 80 20 "${dialog_options[@]}" 3>&1 1>&2 2>&3)

    if [[ -z "$disk" ]]; then
        debug $DEBUG_ERROR "No disk selected"
        error "No disk selected!"
    fi

    DISK="/dev/disk/by-id/$disk"
    debug $DEBUG_INFO "Disk selected: $DISK"
    printf "%s\n" "${bold}Disk selected: $DISK"
}