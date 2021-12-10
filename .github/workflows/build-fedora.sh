#!/bin/bash

set -eux
set -o pipefail

# shellcheck disable=SC2206
PHASES=(${@:-DEPS INITRD})

for phase in "${PHASES[@]}"; do
    case "$phase" in
        DEPS)
            echo "Installing necessary dependencies"
            dnf -y install dnf-plugins-core kernel-core mkosi python3-pyxattr systemd zstd
            ;;
        INITRD)
            rm -fr mkosi.output

            # Can't use `uname -r`, since we're in a container
            KVER="$(rpm -q kernel-core --qf "%{version}-%{release}.%{arch}\n" | sed 1q)"
            [[ -e "kernel-core-$KVER.rpm" ]] || dnf -y download "kernel-core-$KVER"
            python3 -m mkosi --default fedora.mkosi \
                             --image-version="$KVER" \
                             --environment=KERNEL_VERSION="$KVER" \
                             -f build
            # Check if the image was indeed generated
            stat "mkosi.output/initrd_$KVER.cpio.zstd"
            ;;
        SYSEXT)
            rm -fr mkosi.output

            # Can't use `uname -r`, since we're in a container
            KVER="$(rpm -q kernel-core --qf "%{version}-%{release}.%{arch}\n" | sed 1q)"
            [[ -e "kernel-core-$KVER.rpm" ]] || dnf -y download "kernel-core-$KVER"
            # Build the base initrd
            python3 -m mkosi --default fedora.mkosi \
                             --image-version="$KVER" \
                             --environment=KERNEL_VERSION="$KVER" \
                             --format=directory \
                             --clean-package-metadata=no \
                             -f build
            # Build the sysext image
            python3 -m mkosi --default fedora.mkosi \
                             --image-version="$KVER-ssh" \
                             --base-image="mkosi.output/initrd_$KVER" \
                             --format=gpt_squashfs \
                             --environment=SYSEXT="initrd-$KVER-ssh" \
                             --package='!*,openssh-server'
            # Check if the image was indeed generated
            stat "mkosi.output/initrd_$KVER-ssh.raw"
            ;;
        *)
            echo >&2 "Unknown phase '$phase'"
            exit 1
    esac
done