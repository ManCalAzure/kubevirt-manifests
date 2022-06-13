# kubevirt-manifests
various manifest file examples for kubevirt based VMs

# Example

## upload image to pv and deploy  
```
cd <directory>
Kubectl apply -f CDI/pv.yml
Kubectl apply -f CDI/pv1.yml
Kubectl apply -f CDI/dv.yml

Use virtctl image-upload command to upload image to pv 

Kubectl apply -f NAD/nad-fxp.yml
Kubectl apply -f NAD/nad-left.yml
Kubectl apply -f NAD/nad-right.yml

Kubectl apply -f vsrx-kubevirt.yml
```
