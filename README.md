# kubevirt-manifests
various manifest file examples for kubevirt based VMs

# Example

## upload image to pv and deploy  
```
cd vsrx_bridged_mode
Kubectl apply -f CDI/pv1.yml
Kubectl apply -f CDI/pv2.yml
Kubectl apply -f CDI/dv.yml

Use virtctl image-upload command to upload image to pv 

Kubectl apply -f NAD/nad_fxp.yml
Kubectl apply -f NAD/nad_left.yml
Kubectl apply -f NAD/nad_right.yml

Kubectl apply -f vsrx_kubevirt.yml
```
