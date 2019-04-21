# -*- mode: ruby -*-
# vi: set ft=ruby :

# Ansible configuration
BOX = "ubuntu/xenial64"
HOSTNAME1 = "vagrant"

# ---- Custom commands run on the main host ----

Vagrant.configure("2") do |config|
  config.vbguest.no_remote = true
  config.vbguest.auto_update = false
  config.vm.synced_folder ".", "/root/go/src/github.com/bitnami-labs/sealed-secrets"

  config.vm.define "vagrant" do |c|
    c.vm.box = BOX
    c.vm.hostname = HOSTNAME1
    c.vm.network :forwarded_port, guest: 22, host: 2222, id: "ssh"
  end

  # Disable logging
  config.vm.provider "virtualbox" do |vb|
    vb.customize [ "modifyvm", :id, "--uartmode1", "disconnected" ]
    vb.cpus = 2
    vb.memory = 2048
  end

  # View the documentation for the provider you're using for more
  # information on available options.
  config.vm.provision "shell", path: "vagrant-bootstrap.sh"

end
