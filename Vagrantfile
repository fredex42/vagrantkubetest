# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure("2") do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://vagrantcloud.com/search.
  config.vm.box = "generic/fedora33"

  # Disable automatic box update checking. If you disable this, then
  # boxes will only be checked for updates when the user runs
  # `vagrant box outdated`. This is not recommended.
  # config.vm.box_check_update = false

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine. In the example below,
  # accessing "localhost:8080" will access port 80 on the guest machine.
  # NOTE: This will enable public access to the opened port
  # config.vm.network "forwarded_port", guest: 80, host: 8080

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine and only allow access
  # via 127.0.0.1 to disable public access
  # config.vm.network "forwarded_port", guest: 80, host: 8080, host_ip: "127.0.0.1"

  # Create a private network, which allows host-only access to the machine
  # using a specific IP.
  # config.vm.network "private_network", ip: "192.168.33.10"

  # Create a public network, which generally matched to bridged network.
  # Bridged networks make the machine appear as another physical device on
  # your network.
  # config.vm.network "public_network"

  # Share an additional folder to the guest VM. The first argument is
  # the path on the host to the actual folder. The second argument is
  # the path on the guest to mount the folder. And the optional third
  # argument is a set of non-required options.
  # config.vm.synced_folder "../data", "/vagrant_data"

  # Provider-specific configuration so you can fine-tune various
  # backing providers for Vagrant. These expose provider-specific options.
  # Example for VirtualBox:
  #
  config.vm.define "control0" do |cp|
    cp.vm.network "private_network", ip: "10.0.0.10"
    cp.vm.provider "virtualbox" do |vb|
    #   # Display the VirtualBox GUI when booting the machine
    #   vb.gui = true
    #
    #   # Customize the amount of memory on the VM
      vb.memory = "2048"
      vb.cpus = 2
    end
    cp.vm.provision :shell, inline: <<-SHELL
    curl -L https://github.com/projectcalico/calico/releases/download/v3.24.5/calicoctl-linux-amd64 -o /tmp/calicoctl
    sudo mv /tmp/calicoctl /usr/local/bin
    sudo chmod a+x /usr/local/bin/calicoctl
    
    SHELL
  end

  config.vm.define "instance0" do |cp|
    cp.vm.network "private_network", ip: "10.0.0.11"
    cp.vm.hostname = "instance0"
    cp.vm.provider "virtualbox" do |vb|
    #   # Display the VirtualBox GUI when booting the machine
    #   vb.gui = true
    #
    #   # Customize the amount of memory on the VM
      vb.memory = "2048"
      vb.cpus = 2
    end
  end

  config.vm.define "instance1" do |cp|
    cp.vm.network "private_network", ip: "10.0.0.12"
    cp.vm.hostname = "instance1"
    cp.vm.provider "virtualbox" do |vb|
    #   # Display the VirtualBox GUI when booting the machine
    #   vb.gui = true
    #
    #   # Customize the amount of memory on the VM
      vb.memory = "2048"
      vb.cpus = 2

    end
  end

  config.vm.provision :file, source: "kubernetes.repo", destination: "/tmp/kubernetes.repo"
  config.vm.provision :file, source: "onboot.sh", destination: "/tmp/onboot.sh"
  config.vm.provision :file, source: "onboot.service", destination: "/tmp/onboot.service"
  config.vm.provision :shell, inline: <<-SHELL
    sudo dnf remove -y zram-generator-defaults
    sudo dnf module enable -y cri-o:1.20
    sudo dnf install -y cri-o 

    sudo systemctl enable cri-o && sudo systemctl start cri-o

    sudo mv /tmp/kubernetes.repo /etc/yum.repos.d/kubernetes.repo
    sudo yum update
    # Set SELinux in permissive mode (effectively disabling it)
    sudo setenforce 0
    sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

    sudo yum install -y kubelet-1.25.5 kubeadm-1.25.5 kubectl-1.25.5 --disableexcludes=kubernetes

    sudo modprobe br_netfilter
    systemctl disable firewalld
    systemctl stop firewalld
    swapoff -a

    sudo bash -c 'echo 1 > /proc/sys/net/ipv4/ip_forward'
    sudo bash -c 'echo net.bridge.bridge-nf-call-iptables = 1 >> /etc/sysctl.conf'
    sudo bash -c 'echo br_netfilter > /etc/modules-load.d/br_netfilter'
    sudo sysctl -p

    sudo systemctl enable --now kubelet

    sudo mv /tmp/onboot.sh /usr/local/bin
    sudo chown root.root /usr/local/bin/onboot.sh
    sudo chmod u+x /usr/local/bin/onboot.sh
    sudo mv /tmp/onboot.service /etc/systemd/system/onboot.service
    systemctl daemon-reload
    systemctl enable onboot
  SHELL
  #
  # View the documentation for the provider you are using for more
  # information on available options.

  # Enable provisioning with a shell script. Additional provisioners such as
  # Ansible, Chef, Docker, Puppet and Salt are also available. Please see the
  # documentation for more information about their specific syntax and use.
  # config.vm.provision "shell", inline: <<-SHELL
  #   apt-get update
  #   apt-get install -y apache2
  # SHELL
end
