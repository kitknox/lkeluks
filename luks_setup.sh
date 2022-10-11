#!/bin/bash

# Convert LKE base Debian install into an encrypted root filesystem on /deb/sdb

export KUBECONFIG=/etc/kubernetes/kubelet.conf
cd /root
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export LUKS_KEY=`openssl rand -base64 4096 | sha256sum | awk '{print $1}'`
if ! lsblk /dev/sdb | grep "NAME"; then
  echo "Invalid disk configuration.  /dev/sdb must be a raw disk to hold encrypted contents.";
  exit 0;
fi
if cryptsetup status secure | grep "/dev/mapper/secure is active and is in use"; then
  echo \"This instance is already running an encrypted filesystem.\";
  exit 0;
fi
while kubectl get nodes | grep SchedulingDisabled; do
  echo "Waiting for all other nodes to leave drain status"
  sleep 10
done

# Move node into maintenance mode and shutdown any still running pods
kubectl drain `hostname` --ignore-daemonsets
systemctl stop kubelet
systemctl stop docker
systemctl stop docker.socket
systemctl stop containerd

# Post install script
cat > /etc/rc.local <<EOF
#!/bin/bash

export KUBECONFIG=/etc/kubernetes/kubelet.conf
cd /root
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
if cryptsetup status secure | grep "/dev/mapper/secure is active and is in use"; then
  kubectl label nodes `hostname` luks=enabled
  kubectl uncordon `hostname`;
  dd if=/dev/zero of=/dev/sda bs=500M status=progress;
  mkfs.ext4 /dev/sda -F;
  rm /etc/rc.local;
  exit 0
fi
EOF
chmod +x /etc/rc.local

# Update grub with static IP as DHCP in initrd is unreliable
IP=`ip addr show $(ip route | awk '/default/ { print $5 }') | grep "inet" | head -n 1 | awk '/inet/ {print $2}' | cut -d'/' -f1`
QUADS=($(echo $IP | tr "." "\n"))
GATEWAY=${QUADS[0]}.${QUADS[1]}.${QUADS[2]}.1
echo "IP:" $IP
echo "Default Gateway: " $GATEWAY
ip=<client-ip>:<server-ip>:<gw-ip>:<netmask>:<hostname>:<device>:<autoconf>:
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\"/GRUB_CMDLINE_LINUX_DEFAULT=\"ip=$IP::$GATEWAY:255.255.255.0::::8.8.8.8\"/" /etc/default/grub
# Disk layout creating 2GB /boot and the remainder for your root filesystem
cat > lke_setup_fdisk.txt << EOF
g
n
1
2048
4096
t
4
n
2

+2G
n
3


w
EOF
fdisk /dev/sdb < lke_setup_fdisk.txt
mkfs.ext4 /dev/sdb2
mkfs.ext4 /dev/sdb3
export DEBIAN_FRONTEND=noninteractive
apt update
apt-get upgrade -yq
apt install -y joe net-tools clevis clevis-systemd clevis-luks clevis-initramfs cryptsetup-initramfs rsync
echo -n $LUKS_KEY | cryptsetup -q luksFormat --type luks2 /dev/sdb3 -d -
echo -n $LUKS_KEY | cryptsetup luksOpen /dev/sdb3 secure -d -
mkfs.ext4 /dev/mapper/secure 
mount /dev/mapper/secure /mnt
mkdir /mnt/boot
mount /dev/sdb2 /mnt/boot/
cd /mnt
rsync -aAX / /mnt/ --exclude /sys/ --exclude /proc/ --exclude /dev/ --exclude /tmp/ --exclude /media/ --exclude /mnt/ --exclude /run/
mkdir sys proc dev tmp media mnt run
mount -t proc none /mnt/proc
mount -o bind /dev /mnt/dev
mount -t sysfs sys /mnt/sys
cat > /mnt/tmp/chroot.sh << EOFF
#!/bin/sh
export LUKS_KEY=$LUKS_KEY
cat > /etc/fstab <<EOF
/dev/mapper/secure	/	ext4	defaults	0	1
/dev/sdb2	/boot	ext4	defaults 0 0
EOF
cat > /etc/crypttab <<EOF
secure	/dev/sdb3	none
EOF
update-grub
grub-install /dev/sdb
echo $LUKS_KEY | clevis luks bind -y -d /dev/sdb3 tang '{"url": "http://50.116.0.10"}' -k -
mkdir /var/tmp
update-initramfs -u -k 'all'
EOFF
chmod +x /mnt/tmp/chroot.sh
chroot /mnt /tmp/chroot.sh
rm /mnt/tmp/chroot.sh
umount /mnt/proc
umount /mnt/dev
umount /mnt/sys
umount /mnt/boot

# Install lindode-cli, change configuration profile to direct disk boot and then reboot.

apt install -y pip
pip3 install linode-cli
LINODE_API_TOKEN=`kubectl -n kube-system get secret linode -o yaml | grep "token:" | awk '{print $2}' | base64 -d`
LINODE_REGION=`kubectl -n kube-system get secret linode -o yaml | grep "region:" | awk '{print $2}' | base64 -d`
HOSTNAME=`hostname`
LINODE_ID=`kubectl get node $HOSTNAME -o yaml | grep providerID | awk '{print $2}' | tr "/" " " | awk '{print $2}'`
echo $LINODE_API_TOKEN
echo $LINODE_REGION
echo $LINODE_ID
cat > cli_setup.txt <<EOF
$LINODE_API_TOKEN
1
1
1
EOF
rm ~/.config/linode-cli
linode-cli < cli_setup.txt > /dev/null
echo "Linodes in Cluster:"
linode-cli linodes list --text
LINODE_CONFIG_ID=`linode-cli linodes configs-list $LINODE_ID --text --no-headers | awk '{print $1}'`
echo "Linode Config ID: " $LINODE_CONFIG_ID
linode-cli linodes config-update $LINODE_ID $LINODE_CONFIG_ID --kernel linode/direct-disk --root_device /dev/sdb --label "LUKS Encrypted Direct Boot"
linode-cli linodes reboot $LINODE_ID
