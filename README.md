# mkosi-initrd — Build Initrd Images Using Distro Packages

Very brief instructions for use on Fedora:
```
mkdir -p /etc/kernel/
echo 'initrd_generator=mkosi-initrd' >>/etc/kernel/install.conf

# Until https://github.com/dracutdevs/dracut/pull/1825 is merged
mkdir -p /etc/kernel/install.d
ln -s /dev/null /etc/kernel/install.d/50-dracut.install

dnf copr enable zbyszek/mkosi-initrd
dnf install mkosi-initrd

# Install a kernel.
# This will trigger /usr/lib/kernel/install.d/50-mkosi-initrd.install.
dnf upgrade kernel
```

See docs/fedora.md for instructions how to build and use an image manually.
As integration is added for other distros, instructions here will be updated.
