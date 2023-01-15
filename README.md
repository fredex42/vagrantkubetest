# vagrantkubetest

## Why

Minikube works very well for most Kubernetes development related stuff. However, we needed to experiment with some
specific cluster configuration options; specifically:

- cri-o containter runtime
- Calico networking
- Kong ingress controller

and to do this in a small but nonetheless clustered environment.

We decided to build a "bare-metal" style cluster and use Vagrant/Virtualbox to make our lives easier

## How

### Prerequisites

1. Virtualbox
2. Vagrant
3. Plenty of RAM and HDD (if everything maxes out, you'll need 18Gb RAM and over 60Gb storage)

### Step one - kickoff

Clone out this repository and cd to it in a terminal window.  Then run:

```bash
vagrant up
```

This should create three VMs all based on Fedora 33 (this is the latest for which there is a prebuilt
Vagrant box).  They should be called `control0`, `instance0` and `instance1`.

They have hard-set IP addresses on a virtualbox "internal network" of `10.0.0.10`, `10.0.0.11` and `10.0.0.12`. If these clash
with any other ranges that you use you should change the addresses in the Vagrantfile and update them in the commands listed
here too.

### Step two - kubeadm

The Vagrant provisioner should already have installed cri-o, disabled selinux and swap as required by kubedam.

Run `vagrant ssh control0` to get onto the control0 node and initiate the kubernetes setup:

```bash
sudo bash
kubeadm init --apiserver-advertise-address 10.0.0.10 --control-plane-endpoint 10.0.0.10:6443 --pod-network-cidr=192.168.0.0/16
mkdir -p ~/.kube
cp /etc/kubernetes/admin.conf ~/.kube/config
kubectl get nodes
```

When `kubeadm init` finishes, it gives you a `kubeadm join` commandline that you can use to join worker nodes onto the cluster.
Make a note of this elsewhere, you'll need it for the next stage.

You should see the node appear in the output of `kubectl get nodes`

If you receive any preflight errors, then do open an Issue on this repo (or even better, fix it and open a PR!)

Then, you should edit the file `/var/lib/kubelet/kubeadm-flags.env` and add the parameter `--node-ip=10.0.0.10` to the line there,
so it reads:
```
KUBELET_KUBEADM_ARGS="--container-runtime=remote --container-runtime-endpoint=unix:///var/run/crio/crio.sock --pod-infra-container-image=registry.k8s.io/pause:3.8 --node-ip=10.0.0.10"
```

You can make this setting active by running `systemctl restart kubelet`

### Step three - CNI

Full installation instructions can be found at https://projectcalico.docs.tigera.io/getting-started/kubernetes/quickstart (though ignore the step about removing
node taints)

In a nutshell:

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.24.5/manifests/tigera-operator.yaml
wget https://raw.githubusercontent.com/projectcalico/calico/v3.24.5/manifests/custom-resources.yaml
vim custom-resources.yaml 
kubectl apply -f custom-resources.yaml 
watch kubectl get pods -n calico-system
```

Where we download the `custom-resources.yaml` manifest and check that our pod networking CIDR matches and that there is nothing untoward
by opening it up with `vim` before applying.

Once all of the pods in the `calico-system` namespace are Running, we should be good to go

### Step four - worker nodes

Run `vagrant ssh instance0` to get onto the first worker node and then (as root), execute the `kubeadm join` command you saved in step two.
Then, you should edit the file `/var/lib/kubelet/kubeadm-flags.env` and add the parameter `--node-ip=10.0.0.11` to the line there,
so it reads:
```
KUBELET_KUBEADM_ARGS="--container-runtime=remote --container-runtime-endpoint=unix:///var/run/crio/crio.sock --pod-infra-container-image=registry.k8s.io/pause:3.8 --node-ip=10.0.0.11"
```

You can make this setting active by running `systemctl restart kubelet`.

Run `vagrant ssh instance1` to get onto the first worker node and then (as root), execute the `kubeadm join` command you saved in step two.
Then, you should edit the file `/var/lib/kubelet/kubeadm-flags.env` and add the parameter `--node-ip=10.0.0.12` to the line there,
so it reads:
```
KUBELET_KUBEADM_ARGS="--container-runtime=remote --container-runtime-endpoint=unix:///var/run/crio/crio.sock --pod-infra-container-image=registry.k8s.io/pause:3.8 --node-ip=10.0.0.12"
```

You can make this setting active by running `systemctl restart kubelet`.

When you run `kubectl get nodes` from `control0` you should now see three nodes:
```
[root@control0 kubelet]# kubectl get nodes -o wide
NAME                   STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                   KERNEL-VERSION            CONTAINER-RUNTIME
control0               Ready    control-plane   41h   v1.25.5   10.0.0.10     <none>        Fedora 33 (Thirty Three)   5.14.18-100.fc33.x86_64   cri-o://1.20.0
instance0              Ready    <none>          41h   v1.25.5   10.0.0.11     <none>        Fedora 33 (Thirty Three)   5.14.18-100.fc33.x86_64   cri-o://1.20.0
instance1              Ready    <none>          37h   v1.25.5   10.0.0.12     <none>        Fedora 33 (Thirty Three)   5.14.18-100.fc33.x86_64   cri-o://1.20.0
```

### Step five - ingress controller