#!/bin/sh

# Set up a Kubernetes cluster that uses Singularity as container runtime.

set -x # Print each command before execution
set -e # fail and abort script if one command fails
set -o pipefail

# Install Singularity ==================================================================================
# https://docs.sylabs.io/guides/3.8/admin-guide/installation.html#installation-on-linux

# Install Dependencies --------------------------------------------------
# ... for rhel-based linux
if [ -x "$(which yum)" ]; then
  sudo yum update -y &&
    sudo yum groupinstall -y 'Development Tools' &&
    sudo yum install -y \
      openssl-devel \
      libuuid-devel \
      libseccomp-devel \
      wget \
      squashfs-tools \
      cryptsetup \
      inotify-tools \
      git \
      nano

# ... for debian-based linux
elif [ -x "$(which apt)" ]; then
  export DEBIAN_FRONTEND=noninteractive &&
    sudo -E apt update &&
    sudo -E apt install -y \
      build-essential \
      libssl-dev \
      uuid-dev \
      libgpgme11-dev \
      libseccomp-dev \
      pkg-config \
      squashfs-tools \
      inotify-tools \
      git
else
  echo "Error: No supported package manager installed (yum or apt)" >&2 && exit 1
fi

# Install Go ----------------------------------------------------------

wget https://go.dev/dl/go1.20.1.linux-amd64.tar.gz

sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf go1.20.1.linux-amd64.tar.gz

# shellcheck disable=SC2016
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile

# reload PATH var to make go command available without new login
source /etc/profile

go version

# Install Singularity --------------------------------------------------

if [ -d singularity ]; then
  rm -r singularity # clean up
fi

# See Singularity releases: https://github.com/sylabs/singularity/releases

# > 3.7.3 following syntax
#export VERSION=3.8.4 && # adjust this as necessary \
#  wget https://github.com/sylabs/singularity/releases/download/v${VERSION}/singularity-ce-${VERSION}.tar.gz &&
#  tar -xzf singularity-ce-${VERSION}.tar.gz &&
#  cd singularity-ce-${VERSION}

# <= 3.7.3 following syntax
export VERSION=3.7.3 && # adjust this as necessary \
  wget https://github.com/sylabs/singularity/releases/download/v${VERSION}/singularity-${VERSION}.tar.gz &&
  tar -xzf singularity-${VERSION}.tar.gz &&
  cd singularity

# Compile
./mconfig &&
  make -C ./builddir &&
  sudo make -C ./builddir install

# enjoy bash shell completion with SingularityCE commands and options
. /usr/local/etc/bash_completion.d/singularity

cd ..

# Install SingularityCRI ==================================================================================
# Source: https://docs.sylabs.io/guides/cri/1.0/user-guide/installation.html

# See Singularity-CRI releases: https://github.com/sylabs/singularity-cri/tags
export CRI_VERSION=1.0.0-beta.7 # adjust this as necessary

if [ -d singularity-cri ]; then
  rm -r singularity-cri # clean up
fi

if [ -d singularity-cri-${CRI_VERSION} ]; then
  rm -r singularity-cri-${CRI_VERSION} # clean up
fi

wget -O singularity-cri-${CRI_VERSION}.tar.gz https://github.com/sylabs/singularity-cri/archive/refs/tags/v${CRI_VERSION}.tar.gz &&
  tar -xzf singularity-cri-${CRI_VERSION}.tar.gz &&
  mv singularity-cri-${CRI_VERSION} singularity-cri

cd singularity-cri

go mod vendor &&
  make &&
  sudo make install

# Configure SingularityCRI

sed -i 's/cniBinDir:.*/cniBinDir: \/usr\/local\/libexec\/singularity\/cni/g' /usr/local/etc/sycri/sycri.yaml
sed -i 's/cniConfDir:.*/cniConfDir: \/usr\/local\/etc\/singularity\/network/g' /usr/local/etc/sycri/sycri.yaml

# Setup SingularityCRI Integrating with Kubernetes ==================================================================================
# Source: https://docs.sylabs.io/guides/cri/1.0/user-guide/k8s.html

cat >/etc/systemd/system/sycri.service <<EOT
[Unit]
Description=Singularity-CRI
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=30
User=root
Group=root
ExecStart=${PWD}/bin/sycri -v 2

[Install]
WantedBy=multi-user.target
EOT

sudo systemctl enable sycri &&
  sudo systemctl start sycri

sudo systemctl status sycri --no-pager -l

cd ..

# Install Kubernetes

# Disable SELinux
setenforce 0 || true # do not fail if already disabled

if [ -f "/etc/sysconfig/selinux" ]; then # rhel based
  sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
elif [ -f "/etc/selinux/config" ]; then # debian based
  sed -i --follow-symlinks 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
  sed -i --follow-symlinks 's/SELINUX=permissive/SELINUX=disabled/g' /etc/selinux/config
fi

# Disable swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# configure system network config
sudo modprobe br_netfilter
sudo modprobe bridge
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1
sudo sysctl -w net.ipv4.ip_forward=1


# Fix for bad cri-tools dependency in kubeadm
# See cri-tools releases: https://github.com/kubernetes-sigs/cri-tools/releases
CRI_TOOLS_VERSION="1.24.2-00"

# See Kubernetes releases: https://kubernetes.io/releases/
export KUBE_VERSION=1.24.2-00

# ... for rhel-based linux
if [ -x "$(which yum)" ]; then
  cat >/etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg	 https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kube*
EOF

  yum install -y kubelet-${KUBE_VERSION} kubeadm-${KUBE_VERSION} kubectl-${KUBE_VERSION} --disableexcludes=kubernetes
  # FIXME ignore cri-tools
  systemctl enable kubelet

# ... for debian-based linux
elif [ -x "$(which apt)" ]; then

  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
  sudo apt-add-repository -y "deb http://apt.kubernetes.io/ kubernetes-xenial main"
  sudo -E apt-get install -y cri-tools=${CRI_TOOLS_VERSION}
  # install cri-tools manually to fix bug: kubeadm does not specify exact version of dependency cri-tools.
  # Therefore always latest version was installed, which checks different and unnecessary requirements of sycri compared to old version
  sudo -E apt-get install -y kubelet=${KUBE_VERSION} kubeadm=${KUBE_VERSION} kubectl=${KUBE_VERSION}

else
  echo "Error: No supported package manager installed (yum or apt)" >&2 && exit 1
fi

# Setup Kubernetes Cluster

cat >/etc/default/kubelet <<EOF
KUBELET_EXTRA_ARGS=--container-runtime=remote \
--container-runtime-endpoint=unix:///var/run/singularity.sock \
--image-service-endpoint=unix:///var/run/singularity.sock
EOF

sudo systemctl restart kubelet
sudo systemctl status kubelet --no-pager -l

kubeadm init --pod-network-cidr=192.168.0.0/16 --cri-socket unix:///var/run/singularity.sock
# FIXME kubeadm init not working

export KUBECONFIG=/etc/kubernetes/admin.conf

kubectl apply -f https://docs.projectcalico.org/v3.8/manifests/calico.yaml

# TODO add testing kubernetes

# TODO add getting kube config
