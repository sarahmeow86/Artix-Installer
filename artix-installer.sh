#!/usr/bin/env bash
# Debug levels
DEBUG_OFF=0
DEBUG_ERROR=1
DEBUG_WARN=2
DEBUG_INFO=3
DEBUG_DEBUG=4

# Default debug level and colors
DEBUG_LEVEL=${DEBUG_LEVEL:-$DEBUG_INFO}
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

    # Copy chroot log if it exists
    if [[ -f "$CHROOT_LOG" ]]; then
        debug $DEBUG_DEBUG "Copying chroot log"
        cp "$CHROOT_LOG" "$log_dir/" || {
            debug $DEBUG_ERROR "Failed to copy chroot log"
            error "Failed to copy: $CHROOT_LOG"
        }
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

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            echo "Artix Installer version $VERSION"
            exit 0
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
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Set pool name or generate UUID if using ZFS
if [[ $FILESYSTEM == "zfs" ]]; then
    if [[ -n "$ZFS_POOL_NAME" ]]; then
        INST_UUID="" # Clear UUID when using custom pool name
    else
        INST_UUID=$(dd if=/dev/urandom of=/dev/stdout bs=1 count=100 2>/dev/null | tr -dc 'a-z0-9' | cut -c-6)
        ZFS_POOL_NAME="rpool_$INST_UUID"
    fi
fi

# Main installation process
perform_installation() {
    debug $DEBUG_INFO "Starting main installation process"

    # Select and configure filesystem
    choose_filesystem || error "Error selecting filesystem"
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
    local var_steps=("installtz" "installhost" "installkrn" "selectdisk")
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