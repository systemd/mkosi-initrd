#!/bin/bash

set -eux
set -o pipefail

# shellcheck disable=SC2206
PHASES=(${@:-DEPS INITRD})
SYSTEMD_LOG_OPTS="systemd.log_target=console udev.log_level=info systemd.default_standard_output=journal+console"

if rpm -q kernel-core >/dev/null; then
    # Can't use `uname -r`, since we're in a container
    KVER="$(sed 1q <(rpm -q kernel-core --qf "%{version}-%{release}.%{arch}\n" | sort -Vr))"
fi

for phase in "${PHASES[@]}"; do
    case "$phase" in
        DEPS)
            echo "Installing necessary dependencies"
            dnf -y install dnf-plugins-core kernel-core mkosi python3-pyxattr qemu-kvm systemd zstd
            ;;
        INITRD)
            rm -fr mkosi.output

            python3 -m mkosi --default fedora.mkosi \
                             --image-version="$KVER" \
                             --environment=KERNEL_VERSION="$KVER" \
                             -f build
            # Check if the image was indeed generated
            stat "mkosi.output/initrd_$KVER.cpio.zstd"

            # Basic boot test
            timeout -k 10 5m qemu-kvm -m 512 -smp "$(nproc)" -nographic \
                                      -initrd "mkosi.output/initrd_$KVER.cpio.zstd" \
                                      -kernel "/usr/lib/modules/$KVER/vmlinuz" \
                                      -append "rd.systemd.unit=systemd-poweroff.service rd.debug $SYSTEMD_LOG_OPTS console=ttyS0"
            ;;
        INITRD_FULLBOOT)
            if [[ ! -e "mkosi.output/initrd_$KVER.cpio.zstd" ]]; then
                echo >&2 "Missing initrd image (run the INITRD phase first)"
                exit 1
            fi

            # Build a basic image to test the initrd with
            mkdir _rootfs
            pushd _rootfs
            # shellcheck source=/dev/null
            source <(grep -E "(ID|VERSION_ID)" /etc/os-release)
            mkosi --distribution="$ID" --release="$VERSION_ID" --format=gpt_btrfs --output=rootfs.img
            popd

            timeout -k 10 5m qemu-kvm -m 1024 -smp "$(nproc)" -nographic \
                                      -initrd "mkosi.output/initrd_$KVER.cpio.zstd" \
                                      -kernel "/usr/lib/modules/$KVER/vmlinuz" \
                                      -drive "format=raw,cache=unsafe,file=_rootfs/rootfs.img" \
                                      -append "root=LABEL=root rd.debug $SYSTEMD_LOG_OPTS console=ttyS0 systemd.unit=systemd-poweroff.service systemd.default_timeout_start_sec=240"
            ;;
        SYSEXT)
            rm -fr mkosi.output

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
