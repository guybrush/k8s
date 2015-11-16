# k8s

**status: proof-of-concept (working but no automated tests yet)**

a bash-script to deploy [kubernetes](http://kubernetes.io) in containers via ssh

this exists mainly because learning-by-doing, soon there will be
officially supported tooling that provides the same mechanism:
[kubernetes/kubernetes#13901](https://github.com/kubernetes/kubernetes/pull/13901)

## usage

all you need is the script `k8s.sh`, everything else is just documentation
and testing. you can edit cluster-settings by just editing the script or
by exporting environment-variables.

```
# <user>@<ip>/<flannel-iface>
export K8S_CONTROLLER="user@1.2.3.4/eth0"
export K8S_WORKERS="user@2.2.3.4/eth1 user@3.2.3.4/eth2"
./k8s.sh init-ssl # creates "./ssl" directory with certs in it
./k8s.sh kube-up # deploys kubernetes (using the certs in "./ssl")
./k8s.sh install-kubectl # install kubectl into /usr/local/bin
./k8s.sh setup-kubectl # setup kubectl (user, cluster and context)
kubectl cluster-info
kubectl get nodes
kubectl get rc,pods,svc,ing,secrets --all-namespaces
```

or just try everything with vagrant (see `Vagrantfile`, it will setup all the
things for you):

```
vagrant up
vagrant ssh controller
kubectl cluster-info
kubectl get nodes
kubectl get rc,pods,svc,ing,secrets --all-namespaces
```

## features

* tested with debian jessie
* deploy with ssh/scp (like [ZJU-SEL/getting-started/docker-baremetal])
* encrypted communication between nodes (like in [coreos/coreos-kubernetes])
  * secured etcd (for flannel) and secured kube-apiserver
* hyperkube based setup (docker containers all the way down like
  [kubernetes/cluster/docker-multinode]
  and [ZJU-SEL/getting-started/docker-baremetal])
* network via [flannel](https://github.com/coreos/flannel) which runs in
  bootstraped docker with ssl-secured etcd
* deploy [kube-system namespace] and [dns] automatically

[coreos/coreos-kubernetes]: https://github.com/coreos/coreos-kubernetes
[kubernetes/cluster/docker-multinode]: https://github.com/kubernetes/kubernetes/blob/f88550a/docs/getting-started-guides/docker-multinode.md
[ZJU-SEL/getting-started/docker-baremetal]: https://github.com/ZJU-SEL/kubernetes/blob/9caa68f/docs/getting-started-guides/docker-multinode.md
[kube-system namespace]: https://github.com/kubernetes/kubernetes/blob/b9cfab87e/cluster/ubuntu/namespace.yaml
[dns]: https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/dns

## notes

short overview about all the things:

* local-node (from where you setup k8s)
  * files
    * ssl/kube-admin.tar
      * kube-ca.pem
      * kube-admin-key.pem
      * kube-admin-cert.pem
    * ssl/kube-controller-<controller-ip>.tar
      * kube-ca.pem
      * kube-controller-key.pem
      * kube-controller-cert.pem
    * ssl/kube-worker-<woker-ip>.tar (every worker gets its own key/cert)
      * kube-ca.pem
      * kube-worker-key.pem
      * kube-worker-cert.pem

* controller-node
  * files
    * `/etc/kubernetes/ssl/kube-ca.pem`
    * `/etc/kubernetes/ssl/kube-controller-cert.pem`
    * `/etc/kubernetes/ssl/kube-controller-key.pem`
    * `/etc/kubernetes/manifests-custom/controller.yml`
      * kube-controller-manager
      * kube-apiserver
      * kube-scheduler
    * `/etc/systemd/system/docker-bootstrap.service`
  * processes
    * docker-bootstrap
      * etcd
      * flannel
    * docker
      * hyperkube:kubelet
        * controller-pod (`/etc/kubernetes/manifests-custom/controller.yml`)
          * hyperkube:controller-manager
          * hyperkube:apiserver
            * listening on `https://0.0.0.0:443`
            * and `http://127.0.0.1:8080`
          * hyperkube:scheduler
      * hyperkube:proxy

* worker-node(s)
  * files
    * `/etc/kubernetes/ssl/kube-worker-ca.pem`
    * `/etc/kubernetes/ssl/kube-worker-cert.pem`
    * `/etc/kubernetes/ssl/kube-worker-key.pem`
    * `/etc/kubernetes/worker-kubeconfig.yaml`
    * `/etc/systemd/system/docker-bootstrap.service`
  * processes
    * docker-bootstrap
      * flannel
        * uses etcd running on the controller-node (secure ssl-connection)
    * docker
      * hyperkube:kubelet
      * hyperkube:proxy

things i dont fully understand yet:

* where does cadvisor run? kubelet has a cli-option `--cadvisor-port=0`
* is there a reason for kube-proxy to run in host-docker? would it be better
  to run it in the kubelet?

features that would be cool to add (maybe):

* add tests for all the things (overlay-network, ingress-controllers,
  persistent-disks, ..) in some structured way
  * via vagrant (for all the distros)
  * on real cluster (clean up after every test)
* make separate ssl-certs for etcd (which runs inside docker-boostrap, for
  flannel)? currently etcd just uses the same certs as the kube-apiserver
* deploy heapster per default? kubedash? influxdb?
* deploy docker-registry in k8s per default (but i think i prefer it to run
  outside)
* provide options to run etcd outside k8s (on dedicated hardware). though i
  think for small clusters it is fine to have just one etcd on the
  controller-node
* implement all the things into kubectl (this would be very nice `:D`)
* support high-availabilty cluster (separate etcd-cluster, multiple
  apiservers that fight for master via raft)
* make all images really small, to speed up everything
  * [Quest for minimal Docker images](http://william-yeh.github.io/docker-mini/#1)
  
this project is free software released under the
[MIT license](http://www.opensource.org/licenses/mit-license.php)
