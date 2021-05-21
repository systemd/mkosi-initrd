# mkosi-initrd — Build Initrd Images Using Distro Packages

Very brief instructions:
```
cd ~/src
git clone https://github.com/keszybz/mkosi
git clone https://github.com/keszybz/mkosi-initrd
cd mkosi-initrd
mkdir mkosi.cache
dnf download kernel-core-5.12.5-300.fc34.x86_64
sudo PYTHONPATH=$HOME/src/mkosi python3 -m mkosi -f -o initrd.cpio.zstd
```
