#!/usr/bin/env bash
# Debug levels
DEBUG_OFF=0
DEBUG_ERROR=1
DEBUG_WARN=2
DEBUG_INFO=3
DEBUG_DEBUG=4
# Default debug level and colors
DEBUG_LEVEL=3  # Default debug level (INFO)
bold=$(tput setaf 2 bold)
bolderror=$(tput setaf 3 bold)
normal=$(tput sgr0)
INST_MNT=$(mktemp -d)
# Only generate UUID if no pool name is provided
INST_UUID=""
ZFS_POOL_NAME=""

# Create log directory and file
mkdir -p /var/log/artix-installer
LOG_FILE="/var/log/artix-installer/install-$(date +%Y%m%d-%H%M%S).log"

# Debug function
debug() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    if [[ $level -le $DEBUG_LEVEL ]]; then
        case $level in
            $DEBUG_ERROR)
                echo "[ERROR] [$timestamp] $message" >> "$LOG_FILE"
                ;;
            $DEBUG_WARN)
                echo "[WARN]  [$timestamp] $message" >> "$LOG_FILE"
                ;;
            $DEBUG_INFO)
                echo "[INFO]  [$timestamp] $message" >> "$LOG_FILE"
                ;;
            $DEBUG_DEBUG)
                echo "[DEBUG] [$timestamp] $message" >> "$LOG_FILE"
                ;;
        esac
    fi
}

# Error handling with debug
cleanup_on_error() {
    debug $DEBUG_WARN "Error occurred, starting cleanup"
    save_logs
    cleanup_mounts
    debug $DEBUG_INFO "Cleanup completed after error"
    exit 1
}

# Modify the existing error() function
error() {
    debug $DEBUG_ERROR "$1"
    printf "%s\n" "${bolderror}ERROR:${normal}\\n%s\\n" "$1" >&2
    
    # Check if mounting has started
    if [[ -d "$INST_MNT" ]] || [[ $FILESYSTEM == "zfs" && $(zpool list "$ZFS_POOL_NAME" 2>/dev/null) ]]; then
        cleanup_on_error
    else
        exit 1
    fi
}

save_logs() {
    debug $DEBUG_INFO "Saving installation logs"
    
    # Create logs directory in script location
    local log_dir="$(dirname "$(realpath "$0")")/logs"
    mkdir -p "$log_dir" || {
        debug $DEBUG_ERROR "Failed to create logs directory"
        error "Failed to create: $log_dir"
    }

    # Copy main installation log
    debug $DEBUG_DEBUG "Copying main installation log"
    cp "$LOG_FILE" "$log_dir/" || {
        debug $DEBUG_ERROR "Failed to copy main install log"
        error "Failed to copy: $LOG_FILE"
    }

    # Copy chroot logs from the installation mount point if they exist
    if [[ -d "$INST_MNT/var/log/artix-installer" ]]; then
        debug $DEBUG_DEBUG "Checking for chroot logs in $INST_MNT/var/log/artix-installer/"
        for chroot_log in "$INST_MNT/var/log/artix-installer"/chroot-*.log; do
            if [[ -f "$chroot_log" ]]; then
                debug $DEBUG_DEBUG "Copying chroot log: $(basename "$chroot_log")"
                cp "$chroot_log" "$log_dir/" || {
                    debug $DEBUG_ERROR "Failed to copy chroot log: $chroot_log"
                    error "Failed to copy: $chroot_log"
                }
            fi
        done
    fi

    debug $DEBUG_INFO "Installation logs saved to: $log_dir"
}

cleanup_mounts() {
    debug $DEBUG_INFO "Starting cleanup process"

    # Remove /install directory from INST_MNT first
    if [[ -d "$INST_MNT/install" ]]; then
        debug $DEBUG_DEBUG "Removing /install directory from mount point"
        rm -rf "$INST_MNT/install" || {
            debug $DEBUG_ERROR "Failed to remove install directory"
            error "Failed to remove: $INST_MNT/install"
        }
    fi   

    # Then unmount everything under INST_MNT
    if mountpoint -q "$INST_MNT"; then
        debug $DEBUG_DEBUG "Force unmounting all filesystems under: $INST_MNT"
        umount -Rl "$INST_MNT" || {
            debug $DEBUG_ERROR "Failed to unmount: $INST_MNT"
            error "Failed to unmount installation directory"
        }
    fi

    # Export ZFS pool if it exists
    if [[ $FILESYSTEM == "zfs" ]]; then
        debug $DEBUG_DEBUG "Checking for ZFS pool: $ZFS_POOL_NAME"
        if zpool list "$ZFS_POOL_NAME" &>/dev/null; then
            debug $DEBUG_INFO "Exporting ZFS pool: $ZFS_POOL_NAME"
            zpool export "$ZFS_POOL_NAME" || {
                debug $DEBUG_ERROR "Failed to export ZFS pool"
                error "Failed to export ZFS pool: $ZFS_POOL_NAME"
            }
        fi
    fi

    # Finally remove the mount point
    if [[ -d "$INST_MNT" ]]; then
        debug $DEBUG_DEBUG "Removing mount point directory"
        rm -rf "$INST_MNT" || {
            debug $DEBUG_ERROR "Failed to remove mount point"
            error "Failed to remove: $INST_MNT"
        }
    fi

    debug $DEBUG_INFO "Cleanup completed successfully"
}

check_swap() {
    debug $DEBUG_INFO "Checking for active swap partitions"
    local active_swaps=($(swapon --show=NAME --noheadings))
    
    if [[ ${#active_swaps[@]} -gt 0 ]]; then
        debug $DEBUG_INFO "Found active swap partitions: ${active_swaps[*]}"
        dialog --infobox "Deactivating active swap partitions..." 5 50
        for swap in "${active_swaps[@]}"; do
            debug $DEBUG_DEBUG "Deactivating swap: $swap"
            swapoff "$swap" || error "Failed to deactivate swap partition: $swap"
        done
        debug $DEBUG_INFO "All swap partitions deactivated"
    else
        debug $DEBUG_DEBUG "No active swap partitions found"
    fi
}

# Check for dialog
debug $DEBUG_INFO "Checking for required packages"
if ! command -v dialog &> /dev/null; then
    debug $DEBUG_WARN "dialog not found, attempting installation"
    pacman -Sy --noconfirm dialog gptfdisk || {
        debug $DEBUG_ERROR "Failed to install required packages"
        error "Failed to install dialog. Please install it manually."
    }
fi

# Check root privileges
debug $DEBUG_INFO "Checking root privileges"
if [[ $EUID -ne 0 ]]; then
    debug $DEBUG_ERROR "Script not running as root"
    dialog --title "Permission Denied" --msgbox "\
${bolderror}ERROR:${normal} This script must be run as root.\n\n\
Please run it with sudo or as the root user." 10 50
    exit 1
fi

# Initialize installation
debug $DEBUG_INFO "Initializing installation environment"
check_swap || error "Error handling swap partitions!"

# Source required scripts
debug $DEBUG_INFO "Sourcing installation scripts"
for script in zfs-live.sh zfs-setup.sh inst_var.sh disksetup.sh installpkgs.sh \
             configuration.sh filesystem.sh efi.sh repoconfig.sh ; do
    debug $DEBUG_DEBUG "Sourcing: $script"
    source "./scripts/$script" || error "Failed to source $script"
done

validate_swap_size() {
    local size="$1"
    # Check if it's a positive integer
    if [[ ! "$size" =~ ^[0-9]+$ ]]; then
        debug $DEBUG_ERROR "Invalid swap size: must be a positive integer"
        return 1
    fi
    # Get disk size to validate against
    if [[ -n "$DISK" ]]; then
        local disk_size=$(lsblk -b -n -d -o SIZE "$DISK")
        disk_size=$((disk_size / 1024 / 1024 / 1024)) # Convert to GB
        if [[ $size -ge $disk_size ]]; then
            debug $DEBUG_ERROR "Swap size ($size GB) must be less than disk size ($disk_size GB)"
            return 1
        fi
    fi
    return 0
}

# Show help information
show_help() {
    cat << EOF
Artix Linux Installer v${VERSION}

Usage: $0 [OPTIONS]

Options:
    -h, --help              Show this help message and exit
    -v, --version          Show version information and exit
    -D, --debug-level N    Set debug level (0-4, default: 3)
                           0: Off, 1: Error, 2: Warning, 3: Info, 4: Debug
    -d, --disk DEVICE      Specify the installation disk device (must use /dev/disk/by-id/ format)
    -f, --filesystem FS    Specify filesystem type (ext4, btrfs, zfs, xfs)
    -p, --pool-name NAME   Specify ZFS pool name (forces ZFS filesystem)
    -t, --timezone ZONE    Specify timezone (e.g., "Europe/Rome")
    -H, --hostname NAME    Specify system hostname
    -s, --swap-size SIZE   Specify swap partition size in GB (must be positive integer)

Examples:
    $0 -D 4 -d /dev/disk/by-id/ata-SanDisk_SSD_PLUS_120GB_123456 -f ext4 -s 8
    $0 --filesystem zfs --pool-name mypool --swap-size 16
EOF
    exit 0
}

validate_timezone() {
    local tz="$1"
    if [[ -f "/usr/share/zoneinfo/$tz" ]]; then
        return 0
    fi
    debug $DEBUG_ERROR "Invalid timezone: $tz"
    return 1
}

# Parse command line arguments
VERSION="1.0.0"

validate_filesystem() {
    local valid_filesystems=("ext4" "btrfs" "zfs" "xfs")
    local fs="$1"

    for valid_fs in "${valid_filesystems[@]}"; do
        if [[ "$fs" == "$valid_fs" ]]; then
            return 0
        fi
    done

    debug $DEBUG_ERROR "Invalid filesystem: $fs"
    return 1
}

validate_debug_level() {
    local level="$1"
    if [[ "$level" =~ ^[0-4]$ ]]; then
        return 0
    fi
    debug $DEBUG_ERROR "Invalid debug level: $level"
    return 1
}

validate_disk_path() {
    local disk_path="$1"
    # Check if path starts with /dev/disk/by-id/
    if [[ ! "$disk_path" =~ ^/dev/disk/by-id/ ]]; then
        debug $DEBUG_ERROR "Invalid disk path format. Must use /dev/disk/by-id/ format"
        return 1
    fi
    # Check if the disk exists
    if [[ ! -b "$disk_path" ]]; then
        debug $DEBUG_ERROR "Disk does not exist: $disk_path"
        return 1
    fi
    return 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            ;;
        -v|--version)
            echo "Artix Installer version $VERSION"
            exit 0
            ;;
        -H|--hostname)
            if [[ -n "$2" ]]; then
                HOSTNAME="$2"
                shift 2
            else
                error "Hostname argument required"
            fi
            ;;
        -t|--timezone)
            if [[ -n "$2" ]]; then
                if validate_timezone "$2"; then
                    TIMEZONE="$2"
                else
                    error "Invalid timezone: $2. Example format: Europe/Rome"
                fi
                shift 2
            else
                error "Timezone argument required"
            fi
            ;;
        -D|--debug-level)
            if [[ -n "$2" ]]; then
                if validate_debug_level "$2"; then
                    DEBUG_LEVEL="$2"
                else
                    error "Invalid debug level: $2. Valid options are 0-4"
                fi
                shift 2
            else
                error "Debug level argument required"
            fi
            ;;
        -d|--disk)
            if [[ -n "$2" ]]; then
                if validate_disk_path "$2"; then
                    DISK="$2"
                else
                    error "Invalid disk path: $2. Must use /dev/disk/by-id/ format"
                fi
                shift 2
            else
                error "Disk argument required"
            fi
            ;;
        -f|--filesystem)
            if [[ -n "$2" ]]; then
                if validate_filesystem "$2"; then
                    FILESYSTEM="$2"
                else
                    error "Invalid filesystem: $2. Valid options are: ${VALID_FILESYSTEMS[*]}"
                fi
                shift 2
            else
                error "Filesystem argument required"
            fi
            ;;
        -p|--pool-name)
            if [[ -n "$2" ]]; then
                ZFS_POOL_NAME="$2"
                FILESYSTEM="zfs"  # Force ZFS filesystem when pool name is provided
                shift 2
            else
                error "Pool name argument required"
            fi
            ;;
        -s|--swap-size)
            if [[ -n "$2" ]]; then
                if validate_swap_size "$2"; then
                    SWAP_SIZE="$2"
                else
                    error "Invalid swap size: $2. Must be a positive integer less than disk size"
                fi
                shift 2
            else
                error "Swap size argument required"
            fi
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Set pool name or generate UUID if using ZFS
if [[ $FILESYSTEM == "zfs" ]]; then
    if [[ -z "$ZFS_POOL_NAME" ]]; then
        # Generate UUID and set pool name if none provided
        INST_UUID=$(dd if=/dev/urandom of=/dev/stdout bs=1 count=100 2>/dev/null | tr -dc 'a-z0-9' | cut -c-6)
        ZFS_POOL_NAME="rpool_$INST_UUID"
        debug $DEBUG_INFO "Generated ZFS pool name: $ZFS_POOL_NAME"
    else
        INST_UUID="" # Clear UUID when using custom pool name
        debug $DEBUG_INFO "Using provided ZFS pool name: $ZFS_POOL_NAME"
    fi
fi

# Main installation process
perform_installation() {
    debug $DEBUG_INFO "Starting main installation process"

    # Select and configure filesystem
    if [[ -z "$FILESYSTEM" ]]; then
        choose_filesystem || error "Error selecting filesystem"
    fi
    debug $DEBUG_INFO "Selected filesystem: $FILESYSTEM"

    # Configure repositories
    debug $DEBUG_INFO "Installing Chaotic AUR"
    chaoticaur || error "Error installing Chaotic AUR!"
    debug $DEBUG_INFO "Adding repositories"
    addrepo || error "Error adding repos!"

    # Install ZFS if selected
    if [[ $FILESYSTEM == "zfs" ]]; then
        debug $DEBUG_INFO "Installing ZFS support"
        installzfs || error "Error installing ZFS!"
    fi

    # Configure installation variables
    debug $DEBUG_INFO "Configuring installation variables"
    local var_steps=("installkrn")
    # Only add hostname selection if no hostname was specified
    if [[ -z "$HOSTNAME" ]]; then
        var_steps+=("installhost")
    fi
    # Only add timezone selection if no timezone was specified
    if [[ -z "$TIMEZONE" ]]; then
        var_steps+=("installtz")
    fi
    # Only add disk selection if no disk was specified
    if [[ -z "$DISK" ]]; then
        var_steps+=("selectdisk")
    fi
    
    for step in "${var_steps[@]}"; do
        debug $DEBUG_DEBUG "Executing: $step"
        $step || error "Error in $step"
    done

    # Set up system
    debug $DEBUG_INFO "Setting up system"
    local setup_steps=(
        "partdrive"
        "setup_filesystem"
        "efiswap"
        "installpkgs"
        "fstab"
        "configure_initramfs"
        "finishtouch"
        "prepare_chroot"
    )
    for step in "${setup_steps[@]}"; do
        debug $DEBUG_DEBUG "Executing: $step"
        $step || error "Error in $step"
    done

    # Finalize installation
    run_chroot

    # Cleanup and finish
    debug $DEBUG_INFO "Installation completed successfully"
    printf "%s\n" "${bold}Installation completed successfully!"
    save_logs
    cleanup_mounts
}

# Set up error handling
trap 'error "Installation interrupted"' INT TERM

# Replace the existing installation code with:
perform_installation