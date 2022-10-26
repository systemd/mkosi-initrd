%global commit 524dea4cb6f06449c899ec4f98712e263c5952f4
%global shortcommit %(c=%commit; echo ${c:1:7})

%global forgeurl https://github.com/systemd/mkosi-initrd/
%forgemeta

Name:           mkosi-initrd
Version:        0.20221026g%{shortcommit}
Release:        %autorelease
Summary:        Generator for initrd images using distro packages

License:        LGPL-2.1-or-later
URL:            %{forgeurl}
Source0:        %{forgesource}
BuildArch:      noarch

Requires:       mkosi
Requires:       rpm
Requires:       dnf
Requires:       dnf-command(download)
Requires:       cpio
Requires:       kmod
Requires:       systemd
Requires:       python3dist(pyxattr)

%description
%{summary}.

%prep
%forgesetup

%global pkgroot /usr/lib/mkosi-initrd

%install
install -Dt %{buildroot}%{pkgroot} mkosi.finalize
install -Dt %{buildroot}%{pkgroot} -m 0644 fedora.mkosi
install -Dt %{buildroot}/usr/lib/kernel/install.d/ kernel-install/50-mkosi-initrd.install

%files
%doc README.md
%doc docs/fedora.md
%pkgroot/mkosi.finalize
%pkgroot/fedora.mkosi
/usr/lib/kernel/install.d/50-mkosi-initrd.install

%changelog
%autochangelog
