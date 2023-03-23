# Kubernetes Cluster based on Singularity

Set up a Kubernetes cluster using Singularity as the container runtime.

For this, a container runtime interface (CRI) for Singularity is needed. It adapts the Singularity container runtime in
a standardized way and therefore enables Kubernetes to use it. A (deprecated) implementation is available here: https://github.com/sylabs/singularity-cri

In general, Kubernetes and Singularity continued evolving while Singularity-CRI was archived in December 2020.

Ultimately, this should help us run Kubernetes workloads on HPC clusters.

## Setup

Execute following as `root` to install and set up Singularity, Singularity-CRI and Kubernetes:

```shell
/bin/bash ./setup.sh
```

> So far tried on Ubuntu 22.04

## Notes
- Based on current knowledge we want singularity version
  - < 3.10.0 because on removed --empty-process flag
  - \>= 3.9.0 because of cgroups


## Debug

### Logs

Show logs of services:
```shell
journalctl -xfu kubelet
```

### CRI 
Debug the CRI using crictl provided by Kubernetes. See https://kubernetes.io/docs/tasks/debug/debug-cluster/crictl/

List all containers:
```shell
crictl --runtime-endpoint unix:///var/run/singularity.sock ps -a
```

List all images:
```shell
crictl --runtime-endpoint unix:///var/run/singularity.sock images
```

## Sources

- https://slateci.io/blog/kubernetes-with-singularity.html
- https://docs.sylabs.io/guides/cri/1.0/user-guide/k8s.html
- https://github.com/sylabs/singularity-cri
- https://github.com/sylabs/wlm-operator/tree/master/vagrant
- https://github.com/sylabs/singularity
- https://www.howtogeek.com/devops/how-to-start-a-kubernetes-cluster-from-scratch-with-kubeadm-and-kubectl/
