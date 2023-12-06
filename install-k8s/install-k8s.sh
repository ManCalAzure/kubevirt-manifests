#!/bin/bash

#Install network tools
apt-get install net-tools
apt-get install jq -y

# Enable kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

#Enabling IP forwarding in Kernel
sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

# Reload sysctl
sudo sysctl --system

#Installing Docker
echo "Installing docker"
apt-get update
apt-get install -y \
	        apt-transport-https \
		        ca-certificates \
			        curl \
				        software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository \
	        "deb https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
		        $(lsb_release -cs) \
			        stable"

apt-get update && apt-get install -y \
	        docker-ce=$(apt-cache madison docker-ce | grep 20.10 | head -1 | awk '{print $3}')

# Create required directories
sudo mkdir -p /etc/systemd/system/docker.service.d

# Create daemon json config file
sudo tee /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

# Start and enable Services
sudo systemctl daemon-reload
sudo systemctl restart docker
sudo systemctl enable docker

#Install Kubernetes
echo "Installing Kubernetes"
apt-get update && apt-get install -y apt-transport-https
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update

#Kubernetes install specific version 1.23.0
apt-get install -qy kubelet=1.23.0-00 kubeadm=1.23.0-00 kubectl=1.23.0-00 --allow-downgrades

kubeadm version
kubeadm config images pull

#Turning swap off
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo swapoff -a

#Ensuring kubet auto starts on boot-up.
sudo systemctl enable kubelet

kubeadm init --pod-network-cidr=10.244.0.0/16
mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install flannel - https://github.com/flannel-io/flannel - networking for Kubernetes - makes easy creation of l3 fabric for K8s. Flanneld runs in each host/allocates subnets...
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

# shellcheck disable=SC2181
if [ $? -ne 0 ]
then
	  echo "Kubectl command execution failed, please check!!!!!"
	    exit 1
fi


alias kcd='kubectl config set-context $(kubectl config current-context) --namespace'

#Installing helm
curl https://baltocdn.com/helm/signing.asc | apt-key add - \
	&& apt-get install apt-transport-https --yes \
	&& echo "deb https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list \
	&& apt-get update \
	&& apt-get install helm \
	&& helm version --short \
	&& helm repo add stable https://charts.helm.sh/stable

#Installing python
åapt-get install python3 -y
apt-get install python3-pip -y

# Install multus - for supporting container with more than a single interface
git clone https://github.com/k8snetworkplumbingwg/multus-cni.git && cd multus-cni
cat ./deployments/multus-daemonset-thick.yml | kubectl apply -f -
