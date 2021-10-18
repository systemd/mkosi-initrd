---
title: Using mkosi-initrd with Fedora
SPDX-License-Identifier: LGPL-2.1-or-later
---

# Building an initramfs image

Some tools are required: `cpio`, `zstd`, a development version of
`mkosi` from git, and the `mkosi-initrd` repository with configuration
for `mkosi`.

```bash
sudo dnf install zstd cpio
git clone https://github.com/systemd/mkosi
git clone https://github.com/systemd/mkosi-initrd
cd mkosi-initrd
```

The initrd is built for a specific kernel version.
`kernel-core.rpm` has the modules that we want,
but also the `vmlinuz` image, which we don't want.
To avoid the installation of the big package, and the additional dependencies,
and the scriptlets that try to call `kernel-install`,
we extract the modules from the package ourselves.
This rpm needs to be downloaded.
We pass `KERNEL_VERSION=…` to tell the scripts what version to install.

```bash
KVER=`uname -r`
dnf download kernel-core-$KVER
sudo PYTHONPATH=$PWD/../mkosi python -m mkosi --default fedora.mkosi -f -o initrd-$KVER.cpio.zst --environment=KERNEL_VERSION=$KVER
```

This should produce an image that is about 60 MB:

```console
$ KVER=5.14.9-300.fc35.x86_64
$ sudo PYTHONPATH=$PWD/../mkosi python -m mkosi --default fedora.mkosi -f -o initrd-$KVER.cpio.zst --environment=KERNEL_VERSION=$KVER
‣ Removing output files…
‣ Detaching namespace
‣ Setting up temporary workspace.
‣ Temporary workspace set up in /var/tmp/mkosi-k3j2xmzy
‣ Running second (final) stage…
‣  Mounting image…
‣  Setting up basic OS tree…
‣  Mounting Package Cache
‣  Installing Fedora Linux…
‣   Mounting API VFS
Fedora 35 - base                            15 kB/s |  15 kB     00:01
Fedora 35 - base                           548 kB/s | 2.7 MB     00:05
Fedora 35 - updates                         23 kB/s |  25 kB     00:01
Dependencies resolved.
=======================================================================
 Package                 Architecture Version         Repository  Size
=======================================================================
Installing:
 bash                    x86_64       5.1.8-2.fc35    fedora     1.7 M
 e2fsprogs               x86_64       1.46.3-1.fc35   fedora     1.0 M
 less                    x86_64       590-1.fc35      fedora     160 k
 lvm2                    x86_64       2.03.11-6.fc35  fedora     1.4 M
 systemd                 x86_64       249.4-2.fc35    fedora     4.2 M
 systemd-udev            x86_64       249.4-2.fc35    fedora     1.5 M
 xfsprogs                x86_64       5.12.0-2.fc35   fedora     1.0 M
Installing dependencies:
...
Transaction Summary
=======================================================================
Install  114 Packages

Total size: 42 M
Installed size: 135 M
Downloading Packages:
...
Complete!
‣   Unmounting API VFS
‣  Unmounting Package Cache
‣  Removing 7 packages…
‣   Mounting API VFS
Dependencies resolved.
=======================================================================
 Package                 Architecture Version       Repository    Size
=======================================================================
Removing:
 shadow-utils            x86_64       2:4.9-3.fc35  @fedora      3.7 M
Removing unused dependencies:
 libsemanage             x86_64       3.2-4.fc35    @fedora      297 k

Transaction Summary
=======================================================================
Remove  2 Packages

Freed space: 3.9 M
...
Complete!
‣   Unmounting API VFS
‣  Recording packages in manifest…
‣  Cleaning dnf metadata…
‣  Cleaning rpm metadata…
‣  Removing files…
‣  Resetting machine ID
‣  Removing random seed
‣  Running finalize script…
Setting up for kernel 5.14.9-300.fc35.x86_64
...
Writing /var/tmp/mkosi-k3j2xmzy/root/etc/initrd-release with PRETTY_NAME='Fedora Linux 35 (Thirty Five) (mkosi-initrd)'
Symlinked /var/tmp/mkosi-k3j2xmzy/root/init → usr/lib/systemd/systemd
Created /var/tmp/mkosi-k3j2xmzy/root/sysroot
Symlinked /var/tmp/mkosi-k3j2xmzy/root/etc/systemd/system/emergency.service → debug-shell.service
Created symlink /var/tmp/mkosi-k3j2xmzy/root/etc/systemd/system/initrd-udevadm-cleanup-db.service → /dev/null.
‣  Unmounting image
‣  Creating archive…
‣ Linking image file…
‣  Changing ownership of output file mkosi.output/initrd-5.14.9-300.fc35.x86_64.cpio.zst to user … (acquired from sudo)…
‣  Changed ownership of mkosi.output/initrd-5.14.9-300.fc35.x86_64.cpio.zst
‣ Linked mkosi.output/initrd-5.14.9-300.fc35.x86_64.cpio.zst
‣ Saving manifest mkosi.output/initrd-5.14.9-300.fc35.x86_64.cpio.zst.manifest
‣  Changing ownership of output file mkosi.output/initrd-5.14.9-300.fc35.x86_64.cpio.zst.manifest to user … (acquired from sudo)…
‣  Changed ownership of mkosi.output/initrd-5.14.9-300.fc35.x86_64.cpio.zst.manifest
‣ Saving report mkosi.output/initrd-5.14.9-300.fc35.x86_64.cpio.zst.changelog
‣  Changing ownership of output file mkosi.output/initrd-5.14.9-300.fc35.x86_64.cpio.zst.changelog to user … (acquired from sudo)…
‣  Changed ownership of mkosi.output/initrd-5.14.9-300.fc35.x86_64.cpio.zst.changelog
‣ Resulting image size is 54.7M, consumes 54.7M.
```

Hint: on repeated runs, it may be useful to add `--with-network=never` if no new packages need to be downloaded.

# Installing the initramfs image

## UEFI

The output image `mkosi.output/initrd-$KVER.cpio.zst` needs to be installed as
`/boot/efi/$(cat /etc/machine-id)/$KVER/initrd` .
`bootctl list` can be used verify the status.

Currently there is no integration with `kernel-install` or other tools.

## Non-EFI

```
cp mkosi.output/initrd-$KVER.cpio.zst /boot/
grubby --copy-default --add-kernel=/boot/vmlinuz-$KVER --initrd=/boot/initrd-$KVER.cpio.zst --title="experimental-$KVER" --make-default
```

# Building system extension images

First we need to create a version of the initrd image that includes the package metadata:

```bash
sudo PYTHONPATH=$PWD/../mkosi python -m mkosi --default fedora.mkosi -f -o initrd-$KVER.d --environment=KERNEL_VERSION=$KVER \
  --format=directory --clean-package-metadata=no
```

Once that's done, we can build a sysext:
```bash
sudo PYTHONPATH=$PWD/../mkosi python -m mkosi --default fedora.mkosi -f -o initrd-$KVER-ssh.sysext \
  --base-image=mkosi.output/initrd-$KVER.d \
  --format=gpt_squashfs --environment=SYSEXT=initrd-$KVER-ssh \
  --package='!*,openssh-server'
```

This should produce an image that is about 1 MB:

```console
$ sudo PYTHONPATH=$PWD/../mkosi python -m mkosi --default fedora.mkosi -f -o initrd-$KVER-ssh.sysext \
  --base-image=mkosi.output/initrd-$KVER.d \
  --format=gpt_squashfs --environment=SYSEXT=initrd-$KVER-ssh \
  --package='!*,openssh-server'
...
‣   Installing Fedora Linux…
‣    Mounting API VFS
Fedora 35 - base                           1.3 kB/s |  15 kB     00:12
Fedora 35 - updates                         37 kB/s |  25 kB     00:00
Dependencies resolved.
======================================================================
 Package                 Architecture Version       Repository   Size
======================================================================
Installing:
 openssh-server          x86_64       8.7p1-2.fc35  fedora      451 k
Installing dependencies:
 libsemanage             x86_64       3.2-4.fc35    fedora      116 k
 openssh                 x86_64       8.7p1-2.fc35  fedora      451 k
 shadow-utils            x86_64       2:4.9-3.fc35  fedora      1.1 M

Transaction Summary
======================================================================
Install  4 Packages

Total size: 2.1 M
Installed size: 6.9 M
...
‣   Resetting machine ID
‣   Running finalize script…
Writing /var/tmp/mkosi-g8wqud3n/root/usr/lib/extension-release.d/extension-release.initrd-5.14.9-300.fc35.x86_64-ssh with NAME='initrd-5.14.9-300.fc35.x86_64-ssh'
‣   Cleaning up overlayfs
‣    Removing overlay whiteout files…
‣   Unmounting image
‣   Creating squashfs file system…
Parallel mksquashfs: Using 4 processors
Creating 4.0 filesystem on /home/zbyszek/src/mkosi-initrd/mkosi.output/.mkosi-squashfsnd45at4h, block size 131072.
...
‣   Inserting generated root partition…
‣    Resizing disk image to 808.0K
‣    Inserting partition of 768.0K...
...
‣ Linked mkosi.output/initrd-5.14.9-300.fc35.x86_64-ssh.sysext
‣ Resulting image size is 808.0K, consumes 776.0K.
```

FIXME: currently systemd refuses to load the sysext image because the file name doesn't match `extension-release.initrd-5.14.9-300.fc35.x86_64-ssh`, or something like that, it expects ".raw", and refuses to follow symlinks.

```console
$ mv mkosi.output/initrd-$KVER.{sysext,raw}
sudo systemd-dissect mkosi.output/initrd-5.14.9-300.fc35.x86_64-ssh.raw
      Name: initrd-5.14.9-300.fc35.x86_64-ssh.raw
      Size: 808.0K

Extension Release: NAME=initrd-5.14.9-300.fc35.x86_64-ssh
                   ID=fedora
                   VERSION_ID=35
                   PLATFORM_ID=platform:f35
                   HOME_URL=https://fedoraproject.org/
                   DOCUMENTATION_URL=https://docs.fedoraproject.org/en-US/fedora/f35/system-administrators-guide/
                   SUPPORT_URL=https://ask.fedoraproject.org/
                   BUG_REPORT_URL=https://bugzilla.redhat.com/
                   PRIVACY_POLICY_URL=https://fedoraproject.org/wiki/Legal:PrivacyPolicy

RW DESIGNATOR PARTITION UUID                       PARTITION LABEL FSTYPE   ARCHITECTURE VERITY GROWFS NODE         PARTNO
ro root       cc911d05-9aca-8c44-bd81-52c5d1783d8c Root Partition  squashfs x86-64       no         no /dev/loop2p1 1
```

# Verity and signatures

TODO: TBD
