#!/bin/sh
# Luke's Auto Rice Boostrapping Script (NARB)
# by Luke Smith <luke@lukesmith.xyz>
# Modified by Nicholas Tay <nkt@outlook.kr>
# License: GNU GPLv3

### OPTIONS AND VARIABLES ###
while getopts ":a:r:b:p:h" o; do case "${o}" in
	h) printf "Optional arguments for custom use:\\n  -r: dotfiles repository (local file or url)\\n  -p: Dependencies and programs csv (local file or url)\\n  -a: AUR helper (must have pacman-like syntax)\\n  -h: Show this message\\n" && exit ;;
	r) dotfilesrepo=${OPTARG} && git ls-remote "$dotfilesrepo" || exit ;;
	b) repobranch=${OPTARG} ;;
	p) progsfile=${OPTARG} ;;
	a) aurhelper=${OPTARG} ;;
	*) printf "Invalid option: -%s\\n" "$OPTARG" && exit ;;
esac done

[ -z "$dotfilesrepo" ] && dotfilesrepo="https://github.com/nicholastay/dotfiles.git"
[ -z "$progsfile" ] && progsfile="https://raw.githubusercontent.com/nicholastay/dotfiles/master/.local/narb/progs.csv"
[ -z "$aurhelper" ] && aurhelper="yay"
[ -z "$repobranch" ] && repobranch="master"

### FUNCTIONS ###
ifinstalled(){ pacman -Qi "$1" >/dev/null 2>&1 ;}

installpkg(){ pacman --noconfirm --needed -S "$1" >/dev/null 2>&1 ;}

error() { clear; printf "ERROR:\\n%s\\n" "$1"; exit;}

welcomemsg() { \
	dialog --title "Welcome!" --msgbox "Welcome to Nick's Auto Rice Bootstrapper!\\n\\nThis script will automatically install a hopefully working Linux desktop, which I use as my main machine.\\n\\n-Nick" 10 60
	}

getuserandpass() { \
	# Prompts user for new username an password.
	name=$(dialog --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit
	while ! echo "$name" | grep "^[a-z_][a-z0-9_-]*$" >/dev/null 2>&1; do
		name=$(dialog --no-cancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	pass1=$(dialog --no-cancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(dialog --no-cancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(dialog --no-cancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done ;}

usercheck() { \
	! (id -u "$name" >/dev/null) 2>&1 ||
	dialog --colors --title "WARNING!" --yes-label "CONTINUE" --no-label "No wait..." --yesno "The user \`$name\` already exists on this system. NARB can install for a user already existing, but it will \\Zboverwrite\\Zn any conflicting settings/dotfiles on the user account.\\n\\nNARB will \\Zbnot\\Zn overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that NARB will change $name's password to the one you just gave." 14 70
	}

preinstallmsg() { \
	dialog --title "Let's get this party started!" --yes-label "Let's go!" --no-label "No, nevermind!" --yesno "The rest of the installation will now be totally automated, so you can sit back and relax.\\n\\nIt will take some time, but when done, you can relax even more with your complete system.\\n\\nNow just press <Let's go!> and the system will begin installation!" 13 60 || { clear; exit; }
	}

adduserandpass() { \
	# Adds user `$name` with password $pass1.
	dialog --infobox "Adding user \"$name\"..." 4 50
	useradd -m -G wheel,video -s /bin/bash "$name" >/dev/null 2>&1 ||
	usermod -a -G wheel,video "$name" && mkdir -p /home/"$name" && chown "$name":"$name" /home/"$name"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2 ;}

refreshkeys() { \
	dialog --infobox "Refreshing Arch Keyring..." 4 40
	pacman --noconfirm -Sy archlinux-keyring >/dev/null 2>&1
	}

newperms() { # Set special sudoers settings for install (or after).
	sed -i "/#NARB/d" /etc/sudoers
	echo "$* #NARB" >> /etc/sudoers ;}

manualinstall() { # Installs $1 manually if not installed. Used only for AUR helper here.
	[ -f "/usr/bin/$1" ] || (
	dialog --infobox "Installing \"$1\", an AUR helper..." 4 50
	cd /tmp || exit
	rm -rf /tmp/"$1"*
	curl -sO https://aur.archlinux.org/cgit/aur.git/snapshot/"$1".tar.gz &&
	sudo -u "$name" tar -xvf "$1".tar.gz >/dev/null 2>&1 &&
	cd "$1" &&
	sudo -u "$name" makepkg --noconfirm -si >/dev/null 2>&1
	cd /tmp || return) ;}

maininstall() { # Installs all needed programs from main repo.
	dialog --title "NARB Installation" --infobox "Installing \`$1\` ($n of $total). $1 $2" 5 70
	installpkg "$1"
	}

gitmakeinstall() {
	dir=$(mktemp -d)
	dialog --title "NARB Installation" --infobox "Installing \`$(basename "$1")\` ($n of $total) via \`git\` and \`make\`. $(basename "$1") $2" 5 70
	git clone --depth 1 "$1" "$dir" >/dev/null 2>&1
	cd "$dir" || exit
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return ;}

aurinstall() { \
	dialog --title "NARB Installation" --infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 5 70
	echo "$aurinstalled" | grep "^$1$" >/dev/null 2>&1 && return
	sudo -u "$name" yes | $aurhelper -S --noconfirm "$1" >/dev/null 2>&1
	}

pipinstall() { \
	dialog --title "NARB Installation" --infobox "Installing the Python package \`$1\` ($n of $total). $1 $2" 5 70
	command -v pip || installpkg python-pip >/dev/null 2>&1
	yes | pip install "$1"
	}

loadprogs() { \
	dialog --title "NARB Installation" --infobox "Loading program list..." 5 70
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) || curl -Ls "$progsfile" | sed '/^#/d' > /tmp/progs.csv
	optionallist=""
	[ -f "/tmp/progs_filtered.csv" ] && rm /tmp/progs_filtered.csv
	while IFS=, read -r tag program optionals comment; do
		echo "$comment" | grep "^\".*\"$" >/dev/null 2>&1 && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		if [ ! -z "$optionals" ]; then
			optionallist="$optionallist \"$program\" \"$comment\" \"$optionals\""
		else
			echo "$tag,$program,$comment" >> /tmp/progs_filtered.csv
		fi
	done < /tmp/progs.csv
	eval "dialog --title \"NARB Installation\" --separate-output --checklist \"Select optional programs.\" 45 80 8$optionallist" 1>&2 2>/tmp/prog_opts 3>&1
	# now need to go thru again to filter out right ones
	# inefficient but whatever...
	while IFS=, read -r tag program optionals comment; do
		if grep -xq "$program" /tmp/prog_opts; then
			echo "$comment" | grep "^\".*\"$" >/dev/null 2>&1 && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
			echo "$tag,$program,$comment" >> /tmp/progs_filtered.csv
		fi
	done < /tmp/progs.csv
	}

installationloop() { \
	total=$(wc -l < /tmp/progs_filtered.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS=, read -r tag program comment; do
		n=$((n+1))
		echo "$comment" | grep "^\".*\"$" >/dev/null 2>&1 && comment="$(echo "$comment" | sed "s/\(^\"\|\"$\)//g")"
		case "$tag" in
			"A") aurinstall "$program" "$comment" ;;
			"G") gitmakeinstall "$program" "$comment" ;;
			"P") pipinstall "$program" "$comment" ;;
			*) maininstall "$program" "$comment" ;;
		esac
	done < /tmp/progs_filtered.csv
	}

putgitrepo() { # Downlods a gitrepo $1 and places the files in $2 only overwriting conflicts
	dialog --infobox "Downloading and installing config files..." 4 60
	[ -z "$3" ] && branch="master" || branch="$repobranch"
	dir=$(mktemp -d)
	[ ! -d "$2" ] && mkdir -p "$2" && chown -R "$name:$name" "$2"
	chown -R "$name:$name" "$dir"
	sudo -u "$name" git clone -b "$branch" "$1" "$dir/gitrepo" >/dev/null 2>&1 &&
	sudo -u "$name" cp -rfT "$dir/gitrepo" "$2"
	}

systembeepoff() { dialog --infobox "Getting rid of that retarded error beep sound..." 10 50
	rmmod pcspkr
	echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf ;}

lightdmadd() {
	# Additional stuff for lightdm wallpaper, etc
	dialog --infobox "Setting up additional lightdm config..." 10 50
	curl -Lso /usr/share/pixmaps/narb-wall.jpg "https://raw.githubusercontent.com/nicholastay/personal/master/images/masterteacher-waterfall-sunset.jpg"
	cat <<- EOF >> /etc/lightdm/lightdm-gtk-greeter.conf
		theme-name=Arc-Dark
		background=/usr/share/pixmaps/narb-wall.jpg
		font-name=mono
	EOF
	installpkg accountsservice
	curl -Lso "/var/lib/AccountsService/icons/$name.png" "https://raw.githubusercontent.com/nicholastay/personal/master/images/penguin-icon.png"
	cat <<- EOF > /var/lib/AccountsService/users/$name
		[User]
		Icon=/var/lib/AccountsService/icons/$name.png
	EOF
	chmod 644 /var/lib/AccountsService/icons/$name.png /var/lib/AccountsService/users/$name
	}

setupblperms() {
	# Additional permission setups for acpilight control
	# https://gitlab.com/wavexx/acpilight
	cat <<- EOF > /etc/udev/rules.d/90-backlight.rules
		SUBSYSTEM=="backlight", ACTION=="add", \
		  RUN+="/bin/chgrp video /sys/class/backlight/%k/brightness", \
		  RUN+="/bin/chmod g+w /sys/class/backlight/%k/brightness"
	EOF
	usermod -a -G video "$name"
}

runtexlive() {
	dialog --title "NARB Addition" --yesno "The TeX Live Installer was detected. Would you like to run the installer now?" 6 70 && \
	clear && \
	[ -f "/home/$name/.dotfiles/texlive.profile" ] && /opt/texlive-installer/install-tl -init-from-profile "/home/$name/.dotfiles/texlive.profile" || /opt/texlive-installer/install-tl
	}

enableservs() {
	dialog --infobox "Enabling the relevant services based on installs..." 10 50
	ifinstalled tlp && systemctl enable tlp && systemctl enable tlp-sleep
	ifinstalled cronie && systemctl enable cronie
	ifinstalled acpilight && setupblperms
	ifinstalled lightdm && systemctl enable lightdm && lightdmadd
	ifinstalled texlive-installer && runtexlive
	}

thinkpadset() {
	if grep -q "ThinkPad" /sys/class/dmi/id/product_family; then
		dialog --infobox "Applying ThinkPad specific tweaks..."

		installpkg xorg-xinput
		# https://wiki.archlinux.org/index.php/TrackPoint
		# Prefer evdev for trackpoint usage
		if xinput --list | grep -q "TPPS/2 IBM TrackPoint"; then
			installpkg xf86-input-evdev
			cat << EOF > /etc/X11/xorg.conf.d/20-thinkpad.conf
Section "InputClass"
    Identifier	"Trackpoint Wheel Emulation"
    Driver "evdev"
    MatchProduct	"TPPS/2 IBM TrackPoint"
    MatchDevicePath	"/dev/input/event*"
    Option		"EmulateWheel"		"true"
    Option		"EmulateWheelButton"	"2"
    Option		"Emulate3Buttons"	"false"
    Option		"XAxisMapping"		"6 7"
    Option		"YAxisMapping"		"4 5"
EndSection
EOF
		fi

		# ThinkPad specific modules for tlp
		ifinstalled tlp && installpkg tp-smapi && installpkg acpi_call
	fi
	}

finalize(){
	dialog --infobox "Finalising..." 10 50
	curl -Lso /home/$name/.config/wall.jpg "https://raw.githubusercontent.com/nicholastay/personal/master/images/stywo-pink-hills.jpg"
	dialog --title "All done!" --msgbox "Congrats! Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place." 12 80
	}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

# Check if user is root on Arch distro. Install dialog.
installpkg dialog ||  error "Are you sure you're running this as the root user and have an internet connection?"

# Welcome user,
welcomemsg || error "User exited."

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exited."

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

### The rest of the script requires no user input.
adduserandpass || error "Error adding username and/or password."

# Refresh Arch keyrings.
# refreshkeys || error "Error automatically refreshing Arch keyring. Consider doing so manually."

dialog --title "NARB Installation" --infobox "Installing \`basedevel\` and \`git\` for installing other software." 5 70
installpkg base-devel
installpkg git
[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
newperms "%wheel ALL=(ALL) NOPASSWD: ALL"

# Make pacman and yay colorful and adds eye candy on the progress bar because why not.
grep "^Color" /etc/pacman.conf >/dev/null || sed -i "s/^#Color/Color/" /etc/pacman.conf
grep "ILoveCandy" /etc/pacman.conf >/dev/null || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;s/^#MAKEFLAGS/MAKEFLAGS/" /etc/makepkg.conf

manualinstall $aurhelper || error "Failed to install AUR helper."

# Check for optionals by loading programs.
loadprogs

# The command that does all the installing. Reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only after
# the user has been created and has priviledges to run sudo without a password
# and all build dependencies are installed.
installationloop

# Install the dotfiles in the user's home directory
putgitrepo "$dotfilesrepo" "/home/$name" "$repobranch"
rm -f "/home/$name/readme.md"
# Switch to our correct config for workdir/bare (having .git recurse always into home is bad...)
sudo -u "$name" mv "/home/$name/.git" "/home/$name/.dotfiles.git"

# Most important command! Get rid of the beep!
systembeepoff

# Enable services based on installs
enableservs

# Thinkpad checks
thinkpadset

# This line, overwriting the `newperms` command above will allow the user to run
# serveral important commands, `shutdown`, `reboot`, updating, etc. without a password.
newperms "%wheel ALL=(ALL) ALL #NARB
%wheel ALL=(ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/wifi-menu,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/systemctl restart NetworkManager,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/yay,/usr/bin/pacman -Syyuw --noconfirm"

# Make zsh the default shell for the user
sed -i "s/^$name:\(.*\):\/bin\/.*/$name:\1:\/bin\/zsh/" /etc/passwd

# Last message! Install complete!
finalize
clear
echo "Thanks for using NARB."
echo ""
ifinstalled lightdm && echo "Since you installed lightdm, you should probably restart." || echo "Feel free to log out and log into your new user and get going right away! X should start automatically."
ifinstalled plymouth-git && echo "\nSince you installed plymouth, note that you must configure it manually. See the Arch Wiki for guidance. A better watermark.png for the spinner theme can be found in .local/narb under your home folder."
