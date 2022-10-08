# Download 
wget https://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64.img

# Resize image
qemu-img resize ubuntu-20.04-server-cloudimg-amd64.img +100G

# Customize vm adding password as juniper123
virt-customize -a ubuntu-20.04-server-cloudimg-amd64.img \
--root-password password:juniper123 \
--hostname ubuntu \
--run-command 'sed -i "s/.*PasswordAuthentication no/PasswordAuthentication yes/g" /etc/ssh/sshd_config' \
--run-command 'sed -i "s/.*PermitRootLogin prohibit-password/PermitRootLogin yes/g" /etc/ssh/sshd_config' \
--upload templates/interfaces.yaml:/etc/netplan/interfaces.yaml \
--run-command 'dpkg-reconfigure openssh-server' \
--run-command 'sed -i "s/GRUB_CMDLINE_LINUX=\"\(.*\)\"/GRUB_CMDLINE_LINUX=\"\1 net.ifnames=1 biosdevname=0\"/" /etc/default/grub' \
--run-command 'update-grub' \
--run-command 'apt-get purge -y cloud-init'
