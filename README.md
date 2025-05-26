# Artix Installer

Artix Installer is a tool designed to simplify and automate the installation process of Artix Linux. It provides a user-friendly interface and scripts to streamline system setup, package installation, and configuration.

## Features

- Guided installation process for Artix Linux
- Automated partitioning and disk setup
- Package selection and installation
- Post-install configuration (users, locales, etc.)
- Customizable scripts and hooks

## Installation

1. Download an Artix live image
2. Flash it on a USB drive (or use Ventoy)
3. Install git :
    ```sh
    sudo pacman -Sy git
    ```
3. Clone this repository:
    ```sh
    git clone https://github.com/yourusername/Artix-Installer.git
    cd Artix-Installer
    ```
## Usage

Run the installer script with appropriate permissions:
```sh
sudo su
./artix-installer.sh
```
Follow the on-screen instructions to complete the installation.

### Optional Flags

The installer supports several optional flags to speed up the process. All flags are optional and can be used to automate or pre-fill steps:

- `-h`, `--help`  
  Show help message and exit.
- `-v`, `--version`  
  Show version information and exit.
- `-D`, `--debug-level N`  
  Set debug level (0-4, default: 3).  
  0: Off, 1: Error, 2: Warning, 3: Info, 4: Debug
- `-d`, `--disk DEVICE`  
  Specify the installation disk device (must use `/dev/disk/by-id/` format).
- `-f`, `--filesystem FS`  
  Specify filesystem type (`ext4`, `btrfs`, `zfs`, `xfs`).
- `-k`, `--kernel KERNEL`  
  Specify kernel to install (`linux`, `linux-zen`, `linux-lts`).
- `-l`, `--locale LOCALE`  
  Specify system locale (e.g., `en_US.UTF-8`).
- `-p`, `--pool-name NAME`  
  Specify ZFS pool name (forces ZFS filesystem).
- `-t`, `--timezone ZONE`  
  Specify timezone (e.g., `Europe/Rome`).
- `-s`, `--swap-size SIZE`  
  Specify swap partition size in GB (must be a positive integer).

These flags are provided to speed up the installation process by allowing you to skip interactive prompts.

#### Examples

```sh
./artix-installer.sh -D 4 -d /dev/disk/by-id/ata-SanDisk_SSD_PLUS_120GB_123456 -f ext4 -k linux-zen -l en_US.UTF-8 -s 8
./artix-installer.sh --filesystem zfs --pool-name mypool --kernel linux-lts --locale en_GB.UTF-8 --swap-size 16
```

## Requirements

- Bash (or compatible shell)
- Artix Linux ISO live environment
- Internet connection (for package downloads)

## Contributing

Contributions are welcome! Please open issues or submit pull requests for improvements and bug fixes.

## License

This project is licensed under the GPL-V3 License. See [LICENSE](LICENSE) for details.

