# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

$controller_vm_memory = 512
$controller_vm_cpus = 1
$worker_count = 1
$worker_vm_memory = 512
$worker_vm_cpus = 1

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  # always use Vagrant's insecure key
  config.ssh.insert_key = false
  config.ssh.forward_agent = true

  config.vm.box = "debian/jessie64"

  (1..$worker_count).each do |i|
    config.vm.define vm_name ="worker%d" % i do |worker|
      worker.vm.hostname = vm_name
      ["vmware_fusion", "vmware_workstation"].each do |vmware|
        worker.vm.provider vmware do |v|
          v.vmx['memsize'] = $worker_vm_memory
          v.vmx['numvcpus'] = $worker_vm_cpus
        end
      end
      worker.vm.provider :virtualbox do |vb|
        vb.memory = $worker_vm_memory
        vb.cpus = $worker_vm_cpus
      end

      ip = "172.17.4.#{i+100}"
      worker.vm.network :private_network, ip: ip
    end
  end


  config.vm.define vm_name = "controller" do |controller|
    controller.vm.hostname = vm_name
    ["vmware_fusion", "vmware_workstation"].each do |vmware|
      controller.vm.provider vmware do |v|
        v.vmx['memsize'] = $controller_vm_memory
        v.vmx['numvcpus'] = $controller_vm_cpus
      end
    end
    controller.vm.provider :virtualbox do |vb|
      vb.memory = $controller_vm_memory
      vb.cpus = $controller_vm_cpus
    end

    controller.vm.network :private_network, ip: "172.17.4.100"

    # config.vm.synced_folder ".", "/vagrant_data"

    # http://foo-o-rama.com/vagrant--stdin-is-not-a-tty--fix.html
    config.vm.provision "fix-no-tty", type: "shell" do |s|
      s.privileged = false
      s.inline = "sudo sed -i '/tty/!s/mesg n/tty -s \\&\\& mesg n/' /root/.profile"
    end

    controller.vm.provision :file, :source => "k8s.sh", :destination => "/home/vagrant/k8s.sh"

    # sad, but i dont know much about vagrant..
    # we need the key to ssh into all the nodes and then provision them
    controller.vm.provision :shell, :inline => (%q{
cat <<EOOOOOF > /home/vagrant/.ssh/id_rsa
-----BEGIN RSA PRIVATE KEY-----
MIIEogIBAAKCAQEA6NF8iallvQVp22WDkTkyrtvp9eWW6A8YVr+kz4TjGYe7gHzI
w+niNltGEFHzD8+v1I2YJ6oXevct1YeS0o9HZyN1Q9qgCgzUFtdOKLv6IedplqoP
kcmF0aYet2PkEDo3MlTBckFXPITAMzF8dJSIFo9D8HfdOV0IAdx4O7PtixWKn5y2
hMNG0zQPyUecp4pzC6kivAIhyfHilFR61RGL+GPXQ2MWZWFYbAGjyiYJnAmCP3NO
Td0jMZEnDkbUvxhMmBYSdETk1rRgm+R4LOzFUGaHqHDLKLX+FIPKcF96hrucXzcW
yLbIbEgE98OHlnVYCzRdK8jlqm8tehUc9c9WhQIBIwKCAQEA4iqWPJXtzZA68mKd
ELs4jJsdyky+ewdZeNds5tjcnHU5zUYE25K+ffJED9qUWICcLZDc81TGWjHyAqD1
Bw7XpgUwFgeUJwUlzQurAv+/ySnxiwuaGJfhFM1CaQHzfXphgVml+fZUvnJUTvzf
TK2Lg6EdbUE9TarUlBf/xPfuEhMSlIE5keb/Zz3/LUlRg8yDqz5w+QWVJ4utnKnK
iqwZN0mwpwU7YSyJhlT4YV1F3n4YjLswM5wJs2oqm0jssQu/BT0tyEXNDYBLEF4A
sClaWuSJ2kjq7KhrrYXzagqhnSei9ODYFShJu8UWVec3Ihb5ZXlzO6vdNQ1J9Xsf
4m+2ywKBgQD6qFxx/Rv9CNN96l/4rb14HKirC2o/orApiHmHDsURs5rUKDx0f9iP
cXN7S1uePXuJRK/5hsubaOCx3Owd2u9gD6Oq0CsMkE4CUSiJcYrMANtx54cGH7Rk
EjFZxK8xAv1ldELEyxrFqkbE4BKd8QOt414qjvTGyAK+OLD3M2QdCQKBgQDtx8pN
CAxR7yhHbIWT1AH66+XWN8bXq7l3RO/ukeaci98JfkbkxURZhtxV/HHuvUhnPLdX
3TwygPBYZFNo4pzVEhzWoTtnEtrFueKxyc3+LjZpuo+mBlQ6ORtfgkr9gBVphXZG
YEzkCD3lVdl8L4cw9BVpKrJCs1c5taGjDgdInQKBgHm/fVvv96bJxc9x1tffXAcj
3OVdUN0UgXNCSaf/3A/phbeBQe9xS+3mpc4r6qvx+iy69mNBeNZ0xOitIjpjBo2+
dBEjSBwLk5q5tJqHmy/jKMJL4n9ROlx93XS+njxgibTvU6Fp9w+NOFD/HvxB3Tcz
6+jJF85D5BNAG3DBMKBjAoGBAOAxZvgsKN+JuENXsST7F89Tck2iTcQIT8g5rwWC
P9Vt74yboe2kDT531w8+egz7nAmRBKNM751U/95P9t88EDacDI/Z2OwnuFQHCPDF
llYOUI+SpLJ6/vURRbHSnnn8a/XG+nzedGH5JGqEJNQsz+xT2axM0/W/CRknmGaJ
kda/AoGANWrLCz708y7VYgAtW2Uf1DPOIYMdvo6fxIB5i9ZfISgcJ/bbCUkFrhoH
+vq/5CIWxCPp0f85R4qxxQ5ihxJ0YDQT9Jpx4TMss4PSavPaBH3RXow5Ohe+bYoQ
NE5OgEXk2wVfZczCZpigBKbKZHNYcelXtTt/nP3rsCuGcM4h53s=
-----END RSA PRIVATE KEY-----
EOOOOOF

cat <<EOOOOOF > /home/vagrant/.ssh/config
Host *
  StrictHostKeyChecking no

EOOOOOF

cat <<EOOOOOF > /home/vagrant/provision.sh
#!/bin/bash
export K8S_CONTROLLER=vagrant@172.17.4.100/eth0
export K8S_WORKERS=vagrant@172.17.4.101/eth0
/home/vagrant/k8s.sh init-ssl -y
/home/vagrant/k8s.sh kube-up -y
/home/vagrant/k8s.sh install-kubectl
/home/vagrant/k8s.sh setup-kubectl -y
kubectl cluster-info
kubectl get nodes
kubectl get rc,pods,svc,secrets --all-namespaces
EOOOOOF

chmod +x /home/vagrant/k8s.sh
chmod +x /home/vagrant/provision.sh
chmod 600 /home/vagrant/.ssh/id_rsa
chown -R vagrant:vagrant /home/vagrant
sudo -u vagrant /home/vagrant/provision.sh
})

  end
end
