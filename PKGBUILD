# Maintainer: Sarah <saretta1986@proton.me>

pkgname=artix-installer
pkgver=1.1.0
pkgrel=1
pkgdesc="Artix Linux Installation Script"
arch=('any')
url="https://github.com/sarahmeow86/Artix-Installer"
license=('GPL')
depends=('bash' 'dialog' 'gptfdisk')
optdepends=('zfs-dkms: for ZFS support')
source=()

package() {
    cd "$srcdir"
    
    # Install main script
    install -Dm755 "$startdir/artix-installer" "$pkgdir/usr/bin/artix-installer"
    
    # Install support scripts
    install -d "$pkgdir/usr/share/artix-installer/scripts"
    for script in "$startdir"/scripts/*; do
        install -Dm755 "$script" "$pkgdir/usr/share/artix-installer/scripts/$(basename $script)"
    done
    
    # Install misc files
    install -d "$pkgdir/usr/share/artix-installer/misc"
    for file in "$startdir"/misc/*; do
        if [ -f "$file" ]; then
            install -Dm644 "$file" "$pkgdir/usr/share/artix-installer/misc/$(basename $file)"
        elif [ -d "$file" ]; then
            cp -r "$file" "$pkgdir/usr/share/artix-installer/misc/"
        fi
    done
    
    # Install configuration directory
    install -d "$pkgdir/etc/artix-installer"
    
    # Install documentation
    install -Dm644 "$startdir/README.md" "$pkgdir/usr/share/doc/artix-installer/README.md"
}