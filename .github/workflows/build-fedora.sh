#!/bin/bash

set -eux
set -o pipefail

# shellcheck disable=SC2206
PHASES=(${@:-DEPS INITRD_BASIC})
SYSTEMD_LOG_OPTS="systemd.log_target=console udev.log_level=info systemd.default_standard_output=journal+console"
MKOSI_CACHE="/var/tmp/mkosiinitrd$(</etc/machine-id).cache"

if [[ ! -d "$MKOSI_CACHE" ]]; then
    mkdir -v "$MKOSI_CACHE"
fi

if rpm -q kernel-core >/dev/null; then
    # Can't use `uname -r`, since we're in a container
    KVER="$(sed 1q <(rpm -q kernel-core --qf "%{version}-%{release}.%{arch}\n" | sort -Vr))"
fi

for phase in "${PHASES[@]}"; do
    case "$phase" in
        DEPS)
            echo "Installing necessary dependencies"
            dnf -y install \
                cryptsetup \
                dnf-plugins-core \
                dnsmasq \
                iproute \
                jq \
                kernel-core \
                mkosi \
                python3-pyxattr \
                qemu-kvm \
                scsi-target-utils \
                systemd \
                zstd
            ;;
        INITRD_BASIC)
            rm -fr mkosi.output
            mkdir mkosi.output
            # Build a basic initrd
            python3 -m mkosi --cache "$MKOSI_CACHE" \
                             --default fedora.mkosi \
                             --image-version="$KVER" \
                             --environment=KERNEL_VERSION="$KVER" \
                             -f build
            # Check if the image was indeed generated
            stat "mkosi.output/initrd_$KVER.cpio.zstd"

            # Build a basic OS image to test the initrd with
            rm -fr _rootfs
            mkdir _rootfs
            pushd _rootfs
            # shellcheck source=/dev/null
            source <(grep -E "(ID|VERSION_ID)" /etc/os-release)
            mkosi --cache "$MKOSI_CACHE" \
                  --distribution="$ID" \
                  --release="$VERSION_ID" \
                  --format=gpt_btrfs \
                  --output=rootfs.img
            popd

            # Sanity check if the initrd is bootable
            timeout -k 10 5m qemu-kvm -m 512 -smp "$(nproc)" -nographic \
                                      -initrd "mkosi.output/initrd_$KVER.cpio.zstd" \
                                      -kernel "/usr/lib/modules/$KVER/vmlinuz" \
                                      -append "rd.systemd.unit=systemd-poweroff.service rd.debug $SYSTEMD_LOG_OPTS console=ttyS0"

            # Boot the initrd with an OS image
            timeout -k 10 5m qemu-kvm -m 1024 -smp "$(nproc)" -nographic \
                                      -initrd "mkosi.output/initrd_$KVER.cpio.zstd" \
                                      -kernel "/usr/lib/modules/$KVER/vmlinuz" \
                                      -drive "format=raw,cache=unsafe,file=_rootfs/rootfs.img" \
                                      -append "root=LABEL=root rd.debug $SYSTEMD_LOG_OPTS console=ttyS0 systemd.unit=systemd-poweroff.service systemd.default_timeout_start_sec=240"

            # Cleanup
            rm -fr mkosi.output _rootfs
            ;;
        INITRD_LUKS)
            rm -fr mkosi.output mkosi.extra
            mkdir mkosi.output mkosi.extra

            luks_passphrase="H3lloW0rld!"
            # Instruct mkosi to copy the password file into the initrd image
            # so we can use it to unlock the rootfs
            echo -ne "$luks_passphrase" >mkosi.extra/luks.passphrase
            # Build the initrd with dm-crypt support
            python3 -m mkosi --cache "$MKOSI_CACHE" \
                             --default fedora.mkosi \
                             --package="cryptsetup" \
                             --image-version="$KVER" \
                             --environment=KERNEL_VERSION="$KVER" \
                             -f build
            # Check if the image was indeed generated
            stat "mkosi.output/initrd_$KVER.cpio.zstd"

            # Build a basic LUKS encrypted OS image to test the initrd with
            # Passphrase is provided by the mkosi.passphrase file created above
            rm -fr _rootfs mkosi.extra
            mkdir _rootfs
            pushd _rootfs
            # Create a LUKS password file for mkosi
            echo -ne "$luks_passphrase" >mkosi.passphrase
            # shellcheck source=/dev/null
            source <(grep -E "(ID|VERSION_ID)" /etc/os-release)
            mkosi --cache "$MKOSI_CACHE" \
                  --distribution="$ID" \
                  --release="$VERSION_ID" \
                  --encrypt=all \
                  --format=gpt_btrfs \
                  --output=rootfs.img
            popd

            # Boot the initrd with an OS image
            lodev="$(losetup --show -f -P _rootfs/rootfs.img)"
            luks_uuid="$(cryptsetup luksUUID "${lodev}p1")"
            echo "LUKS rootfs UUID: $luks_uuid"
            losetup -d "$lodev"
            luks_cmdline="rd.luks.key=/luks.passphrase rd.luks.uuid=$luks_uuid"
            timeout -k 10 5m qemu-kvm -m 1024 -smp "$(nproc)" -nographic \
                                      -initrd "mkosi.output/initrd_$KVER.cpio.zstd" \
                                      -kernel "/usr/lib/modules/$KVER/vmlinuz" \
                                      -drive "format=raw,cache=unsafe,file=_rootfs/rootfs.img" \
                                      -append "$luks_cmdline root=LABEL=root rd.debug $SYSTEMD_LOG_OPTS console=ttyS0 systemd.unit=systemd-poweroff.service systemd.default_timeout_start_sec=240"

            # Cleanup
            rm -fr mkosi.output mkosi.extra mkosi.passphrase
            ;;
        INITRD_ISCSI)
            rm -fr mkosi.output
            mkdir mkosi.output
            # Build the initrd with iSCSI support
            python3 -m mkosi --cache "$MKOSI_CACHE" \
                             --default fedora.mkosi \
                             --package="NetworkManager,iscsi-initiator-utils" \
                             --image-version="$KVER" \
                             --environment=KERNEL_VERSION="$KVER" \
                             -f build
            ## Check if the image was indeed generated
            stat "mkosi.output/initrd_$KVER.cpio.zstd"

            # Build a basic image to test the initrd with
            rm -fr _rootfs
            mkdir _rootfs
            pushd _rootfs
            # shellcheck source=/dev/null
            source <(grep -E "(ID|VERSION_ID)" /etc/os-release)
            mkosi --cache "$MKOSI_CACHE" \
                  --distribution="$ID" \
                  --release="$VERSION_ID" \
                  --format=gpt_btrfs \
                  --output=rootfs.img
            popd

            # Setup a local iSCSI target
            target_name="iqn.2022-01.com.example:iscsi.initrd.test"
            pgrep tgtd || /usr/sbin/tgtd
            tgtadm --lld iscsi --op new --mode target --tid=1 --targetname "$target_name"
            tgtadm --lld iscsi --op new --mode logicalunit --tid 1 --lun 1 -b "$PWD/_rootfs/rootfs.img"
            tgtadm --lld iscsi --op update --mode logicalunit --tid 1 --lun 1
            tgtadm --lld iscsi --op bind --mode target --tid 1 -I ALL
            tgtadm --lld iscsi --op show --mode target

            ip link add name initrd0 type bridge
            ip addr add 10.10.10.1/24 dev initrd0
            ip link set initrd0 up
            dnsmasq --interface=initrd0 --bind-interfaces --dhcp-range=10.10.10.10,10.10.10.100
            grep -q initrd0 /etc/qemu/bridge.conf || echo "allow initrd0" >>/etc/qemu/bridge.conf

            iscsi_cmdline="ip=dhcp netroot=iscsi:10.10.10.1::::$target_name"
            timeout -k 10 5m qemu-kvm -m 1024 -smp "$(nproc)" -nographic -nic bridge,br=initrd0 \
                                      -initrd "mkosi.output/initrd_$KVER.cpio.zstd" \
                                      -kernel "/usr/lib/modules/$KVER/vmlinuz" \
                                      -append "$iscsi_cmdline root=LABEL=root rd.debug $SYSTEMD_LOG_OPTS console=ttyS0 systemd.unit=systemd-poweroff.service systemd.default_timeout_start_sec=240"

            # Cleanup
            tgtadm --lld iscsi --op delete --mode target --tid=1
            pkill -INT tgtd
            pkill dnsmasq
            rm -fr mkosi.output _rootfs
            ;;
        SYSEXT)
            rm -fr mkosi.output
            mkdir mkosi.output

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

            # Cleanup
            rm -fr mkosi.output
            ;;
        *)
            echo >&2 "Unknown phase '$phase'"
            exit 1
    esac
done
