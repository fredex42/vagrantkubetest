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
3. Plenty of RAM and HDD (if everything maxes out, you'll need 18Gb RAM and over 60Gb storage not to mention more than 8 cores)

### Step one - kickoff

Clone out this repository and cd to it in a terminal window.  Then run:

```bash
export VAGRANT_EXPERIMENTAL="disks"
vagrant up
```

This should create three VMs all based on Fedora 33 (this is the latest for which there is a prebuilt
Vagrant box).  They should be called `control0`, `instance0` and `instance1`.

It's very important to set `VAGRANT_EXPERIMENTAL="disks"` before running `vagrant up`. This allows Vagrant to
provision extra storage on the two worker nodes - 30Gb each for a total of 60Gb cluster storage.  This is **not** 
formatted or initialised in the vagrant provisioning, they are used by Ceph later in the setup process which
formats them itself.

The three VMs have hard-set IP addresses on a virtualbox "internal network" of `10.0.0.10`, `10.0.0.11` and `10.0.0.12`. If these clash
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

One of our objectives was to test out the Kong ingress controller.  In order to get this active, you'll need to initialise it from the standard setup
and then customise it to make it work better with bare-metal.

See https://docs.konghq.com/kubernetes-ingress-controller/2.8.x/deployment/minikube/ for more details.

```bash
kubectl create -f https://raw.githubusercontent.com/Kong/kubernetes-ingress-controller/v2.8.0/deploy/single/all-in-one-dbless.yaml
kubectl delete -n kong deployment ingress-kong
kubectl delete -n kong service kong-proxy
```

Wait, I just deleted the deployment?!

Yes you did.  We need to replace it with a Daemonset.

```bash
kubectl apply -f /home/vagrant/manifests/kongds.yaml
```

`kongds.yaml` is a copy of the Deployment from the `all-in-one-dbless.yaml` manifest but adapted to make it into a DaemonSet and tell
it to bind ports 80 and 443 on all nodes.

Once this is up and running (`watch -n 2 kubectl get pods -n kong`), you should be able to curl it _from your host system_:
```
curl http://10.0.0.12/ -D-
HTTP/1.1 404 Not Found
Date: Sun, 15 Jan 2023 13:57:55 GMT
Content-Type: application/json; charset=utf-8
Connection: keep-alive
Content-Length: 48
X-Kong-Response-Latency: 25
Server: kong/3.0.2

{"message":"no Route matched with those values"}⏎  

curl https://10.0.0.12/ -D- -k
HTTP/2 404 
date: Sun, 15 Jan 2023 13:58:19 GMT
content-type: application/json; charset=utf-8
content-length: 48
x-kong-response-latency: 2
server: kong/3.0.2

{"message":"no Route matched with those values"}⏎
```

(we still need to use -k for https because there is no proper HTTPS cert set up yet)

### Step six - but does it _work_ ?

OK, so now we need to test it out.  You can use the `apachetest.yaml` manifest for this, it deploys a simple Apache httpd server
with a Service in front of it and an ingress to route to it.

```bash
kubectl apply -f /home/vagrant/manifests/apachetest.yaml
watch -n 2 kubectl get pods
```
(wait until it loads up, obvs.)

Firstly, exec onto the pod (the suffixes will be different on your system, use `kubectl get pods` to find the correct name):

```bash
kubectl exec -it httpd-deployment-nautilus-dfbf5fb65-28ckv -- /bin/bash
root@httpd-deployment-nautilus-dfbf5fb65-28ckv:/usr/local/apache2# curl http://localhost -D-
bash: curl: command not found
root@httpd-deployment-nautilus-dfbf5fb65-28ckv:/usr/local/apache2# apt-get update && apt-get install curl
.
.
.
.
root@httpd-deployment-nautilus-dfbf5fb65-28ckv:/usr/local/apache2# curl http://localhost -D-
HTTP/1.1 200 OK
Date: Sun, 15 Jan 2023 14:02:25 GMT
Server: Apache/2.4.54 (Unix)
Last-Modified: Mon, 11 Jun 2007 18:53:14 GMT
ETag: "2d-432a5e4a73a80"
Accept-Ranges: bytes
Content-Length: 45
Content-Type: text/html

<html><body><h1>It works!</h1></body></html>
root@httpd-deployment-nautilus-dfbf5fb65-28ckv:/usr/local/apache2# exit
```

OK so that is the output we expect to see from the server.

Try it from your _host system_:

```bash
curl https://10.0.0.12 -D- -k
HTTP/2 404 
date: Sun, 15 Jan 2023 14:03:30 GMT
content-type: application/json; charset=utf-8
content-length: 48
x-kong-response-latency: 1
server: kong/3.0.2

{"message":"no Route matched with those values"}
```

Huh? Check the path under which the ingress is configured:

```yaml
  - http:
      paths:
      - path: /testpath
        pathType: ImplementationSpecific
```

Now try again:

```
curl https://10.0.0.12/testpath -D- -k
HTTP/2 200 
content-type: text/html; charset=UTF-8
content-length: 45
date: Sun, 15 Jan 2023 14:03:26 GMT
server: Apache/2.4.54 (Unix)
last-modified: Mon, 11 Jun 2007 18:53:14 GMT
etag: "2d-432a5e4a73a80"
accept-ranges: bytes
x-kong-upstream-latency: 68
x-kong-proxy-latency: 4
via: kong/3.0.2

<html><body><h1>It works!</h1></body></html>
```

Great! We got access to our Apache pod(s) from the outside world, with SSL termination, and the headers are telling us that Kong is working just fine to forward
the messages.

If you use `https://10.0.0.11` instead of `https://10.0.0.12` you should see exactly the same result.

### Step seven - storage

We are almost in a position where we can start deploying apps now.  However, we still need to have some kind of persistent storage available.

Kubernetes have recently thinned down the offerings with the result that there really aren't many options for bare-metal.  Fortunately, the
Ceph project gives us a fully supported and integrated storage solution.

There are many differing installation instructions across the Web but the simplest is to use the Kubernetes Operator that the Ceph maintainers
supply, which is called `rook`.  See https://rook.io/docs/rook/v1.10/Getting-Started/intro/ for more details.

This provisions Ceph as an application _within_ the Kubernetes cluster itself and also registers it as a CSI plugin to provision storage.
The following instructions are taken from https://rook.io/docs/rook/v1.10/Getting-Started/quickstart and https://rook.io/docs/rook/v1.10/Storage-Configuration/Block-Storage-RBD/block-storage/

```bash
git clone --single-branch --branch v1.10.9 https://github.com/rook/rook.git
cd rook/deploy/examples
kubectl create -f crds.yaml -f common.yaml -f operator.yaml
kubectl create -f cluster.yaml
watch -n 2 kubectl get pods -n rook-ceph
```

It will take some time for everything to come up.  This will provision the application itself, but it still needs configuring and associating
with our cluster.  

If you're concerned about whether it's working or not, follow the instructions at https://rook.io/docs/rook/v1.10/Troubleshooting/ceph-toolbox/ to
access the Ceph toolbox and use the `ceph status` command in there to see what is going on.

Now, we need to configure a storage pool on Ceph and associate it with a storage class:

```bash
kubectl apply -f /home/vagrant/manifests/ceph-storage-class.yaml
kubectl get storageclass
```

You should see that the new storage class is now present.

Finally, we need to mark this as the "default" storage class, so that the prexit-local components will use it without specific configuration

```bash
kubectl patch storageclass rook-ceph-block -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

#### Shared storages

We have just provisioned ceph block storage, which is great for databases and other things that require private storages. However, if you want
to provision a _shared_ storage (ReadWriteMulti for example) this will fail with the error 

```
multi node access modes are only supported on rbd `block` type volumes
```

This error message is in fact wrong, it should read that multi-node access modes are **not** supported on rbd "block" type volumes.  We must
provision a shared filesystem type for this to work.

Fortunately, that's pretty easy:

```bash
kubectl apply -f manifests/ceph-filesystem.yaml
```

This will provision a new Cephfs filesystem and will then provision a Storage Class that refers to it.

If you see the "multi node access modes..." error, then find the relevant persistent volume claim template and insert the line
`storageClass: rook-cephfs` into the `spec` block in order to use the correct storage class.


And that's it! When you bring up a StatefulSet or another Persistent Volume Claim it will be serviced by Ceph unless it specifically requests
another storage class.

### Step eight - prexit-local

OK, so now we should be ready to go! Head over to https://gitlab.com/codmill/customer-projects/guardian/prexit-local and start following the instructions
there to get some components set up. Happy hacking!
