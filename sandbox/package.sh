#!/bin/bash

sudo apt-get -y install alien gcc

PROGRAMNAME=appimage-sandbox
VERSION=0.1
ARCH=amd64
OUTPUT_FILENAME="${PROGRAMNAME}_${VERSION}_${ARCH}.deb"

echo "creating deb for '${PROGRAMNAME}'; output '${OUTPUT_FILENAME}'"

mkdir -v -p debian/DEBIAN
cp -rf ./src/* ./debian/

gcc loopmounter.c -o debian/usr/bin/loopmounter
strip debian/usr/bin/loopmounter

# Quick and dirty hack until bubblewrap is packaged in distros
wget -c "https://github.com/probonopd/bubblewrap/releases/download/binary/bwrap" -O ./debian/usr/bin/bwrap

cat "" > "${DOCSDIR}/copyright"

mkdir -p debian/usr/share/doc/${PROGRAMNAME}/

find debian/usr -type d -exec chmod 0755 {} \;

echo "" | gzip -9 - -c -f > debian/usr/share/doc/${PROGRAMNAME}/changelog.gz

# round((size in bytes)/1024)
INSTALLED_SIZE=$(du -s debian/usr | awk '{x=$1/1024; i=int(x); if ((x-i)*10 >= 5) {f=1} else {f=0}; print i+f}')
echo "size=${INSTALLED_SIZE}"

echo "Package: ${PROGRAMNAME}
Version: ${VERSION}
Priority: optional
Architecture: ${ARCH}
Depends: bash (>=4.0)
Installed-Size: ${INSTALLED_SIZE}
Maintainer: Simon Peter <probono@puredarwin.org>
Description: Run AppImages inside a read-only sandbox 
 Registers the AppImage file format with a helper that runs
 them inside a sandbox with read-only filesystem access
 if the executable bit is not set." > debian/DEBIAN/control

find ./debian/ -type d | xargs chmod 755
find ./debian/ -type f -exec chmod 0644 {} \;
chmod 755 debian/usr/bin/*

sudo chown root:root debian/usr/bin/loopmounter
sudo chmod 4755 debian/usr/bin/loopmounter

fakeroot dpkg-deb --build debian
mv -v debian.deb "${OUTPUT_FILENAME}"
find debian/
lintian "${OUTPUT_FILENAME}"

sudo alien --to-rpm  *.deb
rm -rf ./debian/
