#!/bin/bash
#
# Author : Ismael Barros² <ismael@barros2.org>
# License : BSD http://en.wikipedia.org/wiki/BSD_license
#
# Registers desktop integration for the given AppImage, including:
#  * Main .desktop file of the AppImage
#   * Menu entry
#   * File and link associations (MIME types)
#  * Icon
#  * Thumbnail

source "$(dirname "$(readlink -f "$0")")/util.sh"


iso_extract() {
	AppImage="$1"
	shift
	LD_LIBRARY_PATH="./usr/lib/:${LD_LIBRARY_PATH}" PATH="./usr/bin:${PATH}" \
		xorriso -indev "$appImage" -osirrox on -extract $@ 2>/dev/null
}

iso_ls() {
	AppImage="$1"
	shift
	LD_LIBRARY_PATH="./usr/lib/:${LD_LIBRARY_PATH}" PATH="./usr/bin:${PATH}" \
		xorriso -indev "$appImage" -osirrox on -ls $@ 2>/dev/null \
		| sed -e "s/^'\(.*\)'$/\1/"
}





appImage="$1"
[ -n "$appImage" ] || exit 1;
[ -f "$appImage" ] || exit 1;
appImageOwner="$(getPathOwner "$appImage")"

file -kib "$appImage" | grep -q "application/x-executable" || exit 1;
file -kib "$appImage" | grep -q "application/x-iso9660-image" || exit 1;

if [ $EUID -eq 0 -a "$appImageOwner" != "root" ] && cmdExists sudo; then
	echo "  Dropping privileges to user '${appImageOwner}'..."
#	su "$appImageOwner" -c "$0" "$appImage"
	sudo -u "$appImageOwner" "$0" "$appImage"
	exit
fi

echo "Registering ${appImage}..."

if [ ! -x "$appImage" ]; then
	echo "  Marking the AppImage executable"
	chmod +x "$appImage"
fi


# We extract the .desktop file inside the AppImage

innerDesktopFilePath=$(iso_ls "$appImage" "/*.desktop" | head -n1)
[ -n "$innerDesktopFilePath" ] || { echo "Desktop file not found" >&2; exit 1; }
desktopFile="$(getAppImageDesktopFile "$appImage")"
appImage_desktopFile="/tmp/$(basename "$desktopFile")"
iso_extract "$appImage" "$innerDesktopFilePath" "$appImage_desktopFile" || { echo "Failed to extract '$innerDesktopFilePath' file to '$appImage_desktopFile'" >&2; exit 1; }


appImage_icon="$(getAppImageIcon "$appImage")"
if [ ! -f "$appImage_icon" ]; then
	# Extract the icon
	innerIconPath=$(desktopFile_getParameter "$appImage_desktopFile" Icon)
	[ -n "$innerIconPath" ] || { echo "Icon file not found" >&2; exit 1; }
	echo "  Extracting icon to ${appImage_icon}..."
	mkdir -p "$(dirname "$appImage_icon")"
	[[ $(echo ${innerIconPath} | grep '.png') == '' ]] && innerIconPath+='.png'
	iso_extract "$appImage" "$innerIconPath" "$appImage_icon" || { echo "Failed to extract icon to '$appImage_icon'" >&2; exit 1; }
fi

appImage_thumbnail="$(getAppImageThumbnail "$appImage")"
if [ ! -f "$appImage_thumbnail" ]; then
	# Link thumbnail
	echo "  Linking thumbnail to ${appImage_thumbnail}..."
	mkdir -p "$(dirname "$appImage_thumbnail")"
	ln -sf "$appImage_icon" "$appImage_thumbnail"
fi


# At last, we generate and register the .desktop file

[ -f "$desktopFile" ] && wasInstalled=1

echo "  Installing desktop file to ${desktopFile}..."
name="$(basename "$appImage")"
appName=$(desktopFile_getParameter "$appImage_desktopFile" Name)
appImage_absolutePath="$(readlink -f "$appImage")"
desktop-file-install \
	--rebuild-mime-info-cache \
	--vendor="AppImage" \
	--set-name="${appName:=$name}" \
	--set-icon="$appImage_icon" \
	--set-comment="Generated by AppImageMonitor on $(date)" \
	--set-key=Type --set-value="Application" \
	--set-key=Exec --set-value="\"$appImage_absolutePath\" %U" \
	--set-key=TryExec --set-value="$appImage_absolutePath" \
	--dir="$(dirname "$desktopFile")" \
	--delete-original \
	"$appImage_desktopFile"

if [ $EUID -eq 0 -a "$appImageOwner" != "root" ]; then
	chown "${appImageOwner}:${appImageOwner}" "$desktopFile" "$appImage_icon" "$appImage_thumbnail"
fi

if [ ! $wasInstalled ] && [ $flag_enableNotifications ] && cmdExists notify-send; then
	notify-send \
		"$name installed" \
		--urgency=low \
		--app-name="AppImage" \
		--icon="$appImage_icon"
fi
