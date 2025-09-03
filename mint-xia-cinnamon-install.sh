#!/bin/bash

set -e

# === USER CONFIGURATION ===
DISK="/dev/nvme0n1"
EFI_SIZE="2G"
SWAP_SIZE="8G"
TARGET="/mnt"
HOSTNAME="linuxmint"
USERNAME="somnath"
PASSWORD="9635"
FULLNAME="Somnath Nandi"
UBUNTU_CODENAME="noble"
MINT_CODENAME="xia"

# === Step 1: Delete existing partitions, preserve GPT ===
echo "🔄 Deleting existing partitions on $DISK (GPT table preserved)..."

for i in $(sgdisk -p $DISK | grep -E '^ +[0-9]+' | awk '{print $1}'); do
    sgdisk -d $i $DISK
done

# Create new partitions
echo "🧱 Creating new partitions..."
sgdisk -n 1:0:+${EFI_SIZE} -t 1:ef00 -c 1:"EFI System Partition" $DISK
sgdisk -n 2:0:+${SWAP_SIZE} -t 2:8200 -c 2:"Swap Partition" $DISK
sgdisk -n 3:0:0 -t 3:8300 -c 3:"Linux Root Partition" $DISK

# Format partitions
echo "🧹 Formatting partitions..."
mkfs.fat -F32 ${DISK}p1
mkswap ${DISK}p2
mkfs.ext4 -F ${DISK}p3

# Mount partitions
echo "📦 Mounting target root and EFI partitions..."
mount ${DISK}p3 $TARGET
mkdir -p $TARGET/boot/efi
mount ${DISK}p1 $TARGET/boot/efi
swapon ${DISK}p2

# === Step 2: Bootstrap Base System ===
echo "📥 Installing base system ($UBUNTU_CODENAME)..."
apt update
apt install -y debootstrap gdisk grub-efi-amd64 linux-image-generic sudo wget gnupg

debootstrap $UBUNTU_CODENAME $TARGET http://archive.ubuntu.com/ubuntu/

# Bind necessary filesystems
echo "🔗 Binding /proc, /sys, /dev, /run..."
mount --types proc /proc $TARGET/proc
mount --rbind /sys $TARGET/sys
mount --make-rslave $TARGET/sys
mount --rbind /dev $TARGET/dev
mount --make-rslave $TARGET/dev
mount --bind /run $TARGET/run
cp /etc/resolv.conf $TARGET/etc/resolv.conf

# === Step 3: Configure in chroot ===
echo "🔧 Configuring system inside chroot..."
chroot $TARGET /bin/bash <<EOF

# Set up hostname
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost" > /etc/hosts
echo "127.0.1.1 $HOSTNAME" >> /etc/hosts

# Add Linux Mint Xia repo
cat > /etc/apt/sources.list <<EOL
deb http://archive.ubuntu.com/ubuntu $UBUNTU_CODENAME main universe multiverse restricted
deb http://archive.ubuntu.com/ubuntu $UBUNTU_CODENAME-updates main universe multiverse restricted
deb http://archive.ubuntu.com/ubuntu $UBUNTU_CODENAME-backports main universe multiverse restricted
deb http://security.ubuntu.com/ubuntu $UBUNTU_CODENAME-security main universe multiverse restricted
deb http://packages.linuxmint.com $MINT_CODENAME main upstream import backport
EOL

# Add Mint GPG key
apt-key adv --keyserver keyserver.ubuntu.com --recv-keys A6616109451BBBF2

# Update and install Cinnamon
apt update
DEBIAN_FRONTEND=noninteractive apt install -y \
    mint-meta-cinnamon \
    lightdm slick-greeter \
    network-manager \
    sudo locales grub-efi-amd64 os-prober

# Set locale
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Create user
useradd -m -c "$FULLNAME" -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd
usermod -aG sudo $USERNAME

# Set root password
echo "root:$PASSWORD" | chpasswd

# Enable services
systemctl enable lightdm
systemctl enable NetworkManager

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
update-grub

EOF

# === Step 4: Cleanup ===
echo "🧼 Cleaning up..."
umount -l $TARGET/dev{/shm,/pts,}
umount -R $TARGET/dev
umount -R $TARGET/proc
umount -R $TARGET/sys
umount -R $TARGET/run
umount -R $TARGET/boot/efi
umount -R $TARGET

swapoff ${DISK}p2

echo "✅ Linux Mint Xia with Cinnamon is installed successfully!"
echo "🔁 You can now reboot and remove the live environment media."
