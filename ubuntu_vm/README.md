# Download and modify VM

## Kubevirt

Ensure Kubevirt env is installed. you can follow steps [here](https://ard92.github.io/2022/05/30/kubevirt.html) to install  

## Clone repo
```
git clone https://github.com/ARD92/kubevirt-manifests.git

cd ubuntu_vm
```

## Modify permissions and pull ubuntu 20.04 image
This will download the ubuntu cloud image and modify the root credentials before it can be used on the kubevirt env.
This is needed because cloud init doesnt seem to work on ubuntu vms. The root password cannot be changed and hence cannot login at all from console.
```
chmod +x get_modify_ubuntu.sh 

./get_modify_ubuntu.sh
```
### Optional step in case virt-customize needs to be installed. 
This can be skipped if all packages are installed already

```
sudo apt-get -y update; sudo apt-get -y install qemu-kvm libvirt-bin ubuntu-vm-builder bridge-utils virt-manager
apt-get install -y net-tools tcpdump wget sshpass
https://linuxhint.com/libvirt_python/
apt install libguestfs-tools
```

## Find the upload proxy
```
kubectl get pods -n cdi -o wide

NAME                               READY   STATUS    RESTARTS   AGE   IP            NODE          NOMINATED NODE   READINESS GATES
cdi-apiserver-76ffb454c9-4mjsr     1/1     Running   0          9h    10.244.1.9    k8s-worker2   <none>           <none>
cdi-deployment-668465f546-4xc87    1/1     Running   0          9h    10.244.2.7    k8s-worker1   <none>           <none>
cdi-operator-64d6dc7f6f-2997n      1/1     Running   0          9h    10.244.1.8    k8s-worker2   <none>           <none>
cdi-uploadproxy-664c777f8f-cb2fn   1/1     Running   0          9h    10.244.1.10   k8s-worker2   <none>           <none>
```

So the IP to be used is `10.244.1.10`

## Deploy
```
# 1st vm 
Kubectl apply -f CDI/pv.yml
Kubectl apply -f CDI/pv1.yml
Kubectl apply -f CDI/dv.yml

# use the correct dv name . In this case dv-ubuntu1. you can find using "kubectl get dv"
virtctl image-upload dv dv-ubuntu1 --size=100Gi --image-path=ubuntu-20.04-server-cloudimg-amd64.img --uploadproxy-url https://10.244.2.69:8443  --insecure --storage-class hostpath-provisioner

Kubectl apply -f NAD/nad-fxp.yml
Kubectl apply -f NAD/nad-intf1.yml
Kubectl apply -f NAD/nad-intf2.yml

kubectl apply -f ubuntu_vm1.yml

# 2nd vm
Kubectl apply -f CDI/vm2/pv.yml
Kubectl apply -f CDI/vm2/pv1.yml
Kubectl apply -f CDI/vm2/dv.yml

# use the correct dv name . In this case dv-ubuntu1. you can find using "kubectl get dv"
virtctl image-upload dv dv-ubuntu2 --size=100Gi --image-path=ubuntu-20.04-server-cloudimg-amd64.img --uploadproxy-url https://10.244.2.69:8443  --insecure --storage-class hostpath-provisioner

Kubectl apply -f NAD/vm2/nad-fxp.yml
Kubectl apply -f NAD/vm2/nad-intf1.yml
Kubectl apply -f NAD/vm2/nad-intf2.yml

kubectl apply -f ubuntu_vm2.yml
```

## Verify VM is running 
```
root@k8s-master:~# kubectl get vm
NAME         AGE    STATUS    READY
ubuntu-kv1   18h    Running   True
ubuntu-kv2   18h    Running   True
vsrx-sriov   123d   Running   True

root@k8s-master:~# kubectl get vmi
NAME         AGE    PHASE     IP             NODENAME      READY
ubuntu-kv1   18h    Running   10.244.2.97    k8s-worker1   True
ubuntu-kv2   18h    Running   10.244.1.138   k8s-worker2   True
vsrx-sriov   123d   Running                  k8s-worker2   True
```

## Login and add IP to interface 

The below file should be copied under `/etc/netplan`. In case it is missing, add the below contents. 
```
root@ubuntu:~# cd /etc/netplan/

root@ubuntu:/etc/netplan# more interfaces.yaml
network:
  ethernets:
    enp1s0:
      dhcp4: yes
      nameservers:
        addresses: [8.8.8.8, 10.85.6.68]
      optional: true
  version: 2
```

### Apply
```
netplan apply
```

### validate
```
root@ubuntu:/etc/netplan# ip addr show dev enp1s0
2: enp1s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc fq_codel state UP group default qlen 1000
    link/ether 52:54:00:68:c6:f5 brd ff:ff:ff:ff:ff:ff
    inet 10.0.2.2/24 brd 10.0.2.255 scope global dynamic enp1s0
       valid_lft 86278656sec preferred_lft 86278656sec
    inet6 fe80::5054:ff:fe68:c6f5/64 scope link
       valid_lft forever preferred_lft forever


root@ubuntu:/etc/netplan# ping 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=110 time=23.1 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=110 time=23.1 ms
```

## Resize the VM root partition
```
root@ubuntu:/etc/netplan# lsblk
NAME    MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT
loop0     7:0    0  67.8M  1 loop /snap/lxd/22753
loop1     7:1    0    48M  1 loop /snap/snapd/17029
loop2     7:2    0  63.2M  1 loop /snap/core20/1623
vda     252:0    0   189G  0 disk
├─vda1  252:1    0 188.9G  0 part /
├─vda14 252:14   0     4M  0 part
└─vda15 252:15   0   106M  0 part /boot/efi

root@ubuntu:fdisk /dev/vda

- press "d" and delete "/root" partition
- press "n" and create the partition
- press "w" to save

root@ubuntu:resize2fs /dev/sda1 
```

