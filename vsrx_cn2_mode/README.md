# Installing vSRX and test hosts in OCP + CN2 + Kubevirt

This document describes the procedure to deploy vSRX in Kubevirt on OCP/CN2 along with two test VMs, one on either side of the vSRX.

## Prerequisites

It is assumed that OCP, CN2 and Kubevirt are already installed along with containerized-data-importer (CDI) to import VMs for use in a k8s environment.

The YAML manifests referenced below are included in the same folder as this document.

## Create Networks

The lab is setup with three networks, plus the default-pod-network in a Namespace called `vsrx`.  The three networks are:

- mgmt
- left
- right

When created with a `NetworkAttachmentDefinition`, it appears that DHCP is disabled by default.  Therefore, we propose to use the CN2 format of creating `VirtualNetwork`s.  Example configs for NADs are visible in `NAD/nad-*.yaml` but the `VirtualNetwork` examples are in `VN/vn-*.yaml`. These manifests include the creation of a `Subnet`, in which we enable DHCP along with assigning DHCP allocation pools and a default GW for the `VirtualNetwork`.

In addition, on the left-hand side of the vSRX, we need a static `RouteTable` that provides a default route towards the vSRX.  This could be achieved with an `InterfaceNetworkRoute` but that requires manually creating (or subsequently editing) a `VirtualMachineInterface` for the left interface of the vSRX.  This is simpler.

The `RouteTable` is created with 

```bash
oc create -f VN/network-rt.yaml
```

Once that static route is created, you can create the networks.

```bash
oc create -f VN/vn-mgmt.yaml
oc create -f VN/vn-left.yaml
oc create -f VN/vn-right.yaml
```

## Create Containerized Disk Image

### Use an online `DataVolume`

Using the tools described in the `CDI/*.yaml` files, create a `StorageClass`, a template `PersistentVolume` and a `DataVolume` to consume the `PV`.  

### Use a local `ContainerDisk`

In a lab, an online data store may not be readily available.  In order to test CN2 + Kubevirt, it's possible to build a ContainerDisk image and push it up to a local registry or individually out to each of the compute nodes.

#### Build the ContainerDisk image

In order to build the `ContainerDisk`, you need to use either `docker`, `nerdctl` or `podman` depending on your CRI (docker, containerd or cri-o respectively).  Since these instructions are focused on OCP, it will use podman.

First, obtain the vsrx image and put it into a new directory

```bash
cd ~
mkdir vsrx3-image-file
cd vsrx-image-file
wget <junos-vsrx3-x86-64-22.4R1.10.qcow2> ## Import from the Juniper customer portal
```

Next, create a `Containerfile` providing instructions on the container build requirements.

```bash
cat << EOF > Containerfile
FROM scratch
ADD --chown=107:107 junos-vsrx3-x86-64-22.4R1.10.qcow2 /disk/
EOF
```

Next, build the image.

```bash
podman build -t vmidisks/vsrx3:22.4R1.10 .
```

And finally, push the image to the registry (or save it, copy it manually to each compute, and then import it into the local registry of each compute node).

```bash
podman push vmidisks/vsrx3:22.4R1.10 <registry-image-url>
```

or

```bash
podman save vmidisks/vsrx3:22.4R1.10 --output vsrx3-22.4R1.10.tgz
scp vsrx3-22.4R1.10.tgz user@compute-node:/var/tmp/
ssh user@compute-node
cd /var/tmp
podman load --input vsrx3-22.4R1.10.tgz
```

## Spawn VMs

The VMs are installed with the vSRX attached to all four VNs but the test VMs (Centos) attached only to the left or right VN respectively.

```bash
oc create -f VM/vsrx-kubevirt.yaml
oc create -f VM/centos-internal.yaml
oc create -f VM/centos-public.yaml
```

You can monitor the progress of the vms with

```bash
oc get vms -n vsrx
```

Once they show `Starting` as the state, you can use `virtctl` to access the console of each and follow their boot progress.

```bash
virtctl console <vm-name>
```

In the vsrx-kubevirt.yaml, we assign static interface addresses to the particular interfaces in order to enable the simple route creation in advance of the VM creation.

```yaml
---
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vsrx-datavolume
  namespace: vsrx
  annotations:
    k8s.v1.cni.cncf.io/networks: |-
      [
        {
          "interface":"net1",
          "name":"mgmt",
          "namespace":"vsrx",
          "ips":["192.168.5.2"]
        },{
          "interface":"net2",
          "name":"left",
          "namespace":"vsrx",
          "ips":["192.168.6.2"]
        },{
          "interface":"net3",
          "name":"right",
          "namespace":"vsrx",
          "ips":["192.168.7.2"]
        }
      ]
spec:
  running: True
  dataVolumeTemplates:
  - metadata:
      creationTimestamp: null
      name: vsrx-dv-url
    spec:
      source:
        http:
          url: http://virt-images.virt-images.svc.cluster.local/junos-vsrx3-x86-64-22.4R1.10.qcow2
      storage:
        accessModes:
        - ReadWriteMany
        resources:
          requests:
            storage: 20G
        storageClassName: ocs-storagecluster-cephfs
        volumeMode: Filesystem
  template:
    metadata:
      labels:
        kubevirt.io/vm: vsrx-datavolume
    spec:
      domain:
        ioThreadsPolicy: auto
        cpu:
          sockets: 1
          cores: 4
          threads: 1
        resources:
          requests:
            memory: 8Gi
            cpu: "4"
          limits:
            cpu: "4"
            memory: 8Gi
        devices:
          useVirtioTransitional: true
          disks:
            - name: rootdisk
              disk:
                bus: virtio
          interfaces:
            - name: default
              masquerade: {}
            - name: mgmt
              bridge: {}
            - name: left
              bridge: {}
            - name: right
              bridge: {}
      volumes:
        - name: rootdisk
          dataVolume:
            name: vsrx-dv-url
      networks:
        - name: default
          pod: {}
        - name: mgmt
          multus:
            networkName: mgmt
        - name: left
          multus:
            networkName: left
        - name: right
          multus:
            networkName: right

```

In `vsrx-kubevirt-containerdisk.yaml` you can see that the changes are minimal except for the way in which the volumes are identified and bound.

```yaml
---
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vsrx-containerdisk
  namespace: vsrx
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: vsrx-containerdisk
      annotations:
        k8s.v1.cni.cncf.io/networks: |-
          [
            {
              "name":"mgmt",
              "namespace":"vsrx",
              "cni-args":null,
              "interface":"ge-0/0/0",
              "ips":["192.168.5.2"]
            },
            {
              "name":"left",
              "namespace":"vsrx",
              "cni-args":null,
              "interface":"ge-0/0/1",
              "ips":["192.168.6.2"]
            },
            {
              "name":"right",
              "namespace":"vsrx",
              "cni-args":null,
              "interface":"ge-0/0/2",
              "ips":["192.168.7.2"]
            }
          ]
    spec:
      domain:
        ioThreadsPolicy: auto
        cpu:
          sockets: 1
          cores: 4
          threads: 1
        resources:
          requests:
            memory: 8Gi
            cpu: "4"
          limits:
            cpu: "4"
            memory: 8Gi
        devices:
          useVirtioTransitional: true
          disks:
            - name: containerdisk
              disk: {}
          interfaces:
            - name: default
              masquerade: {}
            - name: mgmt
              bridge: {}
            - name: left
              bridge: {}
            - name: right
              bridge: {}
      volumes:
        - name: containerdisk
          containerDisk:
            image: vmidisks/vsrx3:22.4R1.10
      networks:
        - name: default
          pod: {}
        - name: mgmt
          multus:
            networkName: mgmt
        - name: left
          multus:
            networkName: left
        - name: right
          multus:
            networkName: right

```
