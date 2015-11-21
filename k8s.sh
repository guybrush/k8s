#!/bin/bash

set -e

HELP="deploy k8s remotely in containers via ssh and scp

usage:

  1) edit settings (just beneath this doc, or export CONTROLLER and WORKERS)
  2) run \`./k8s.sh init-ssl\` (it will create ./ssl directory)
  3) run \`./k8s.sh kube-up\` (it will ssh into all the machines and setup k8s)
  4) run \`sudo ./k8s.sh install-kubectl\` (install kubectl into /usr/local/bin locally)
  5) run \`./k8s.sh setup-kubectl\` (configure kubectl cluster, user and context)
  6) run \`./k8s.sh kube-down\` (it will ssh into all the machines and uninstall k8s)

example:

  # <user>@<ip>/<flannel-interface>
  export K8S_CONTROLLER=user@192.168.0.1/eth0
  export K8S_WORKERS=user@192.168.0.2/eth1 user@192.168.0.3/eth2
  export K8S_FLANNEL_NETWORK=10.1.0.0/16
  export K8S_SERVICE_IP_RANGE=10.2.0.0/16
  export K8S_DNS_SERVICE_IP=10.2.0.10
  ./k8s.sh init-ssl
  ./k8s.sh kube-up
  sudo ./k8s.sh install-kubectl
  ./k8s.sh setup-kubectl
  kubectl cluster-info
  kubectl get nodes
  kubectl get rc,pods,svc,ing,secrets --all-namespaces
  kubectl proxy

further information: https://github.com/guybrush/k8s
"

################################################################################

# <user>@<ip>/<flannel-interface>
K8S_CONTROLLER=${K8S_CONTROLLER:-"vagrant@10.0.0.201/eth1"}
K8S_WORKERS=${K8S_WORKERS:-"vagrant@10.0.0.202/eth1 vagrant@10.0.0.203/eth1"}

K8S_FLANNEL_NETWORK=${K8S_FLANNEL_NETWORK:-"10.1.0.0/16"}
K8S_SERVICE_IP_RANGE=${K8S_SERVICE_IP_RANGE:-"10.2.0.0/16"}
K8S_DNS_SERVICE_IP=${K8S_DNS_SERVICE_IP:-"10.2.0.10"}

# K8S_IMAGE_HYPERKUBE=${K8S_IMAGE_HYPERKUBE:-"gcr.io/google_containers/hyperkube:v1.1.0"}
# K8S_IMAGE_HYPERKUBE=${K8S_IMAGE_HYPERKUBE:-"gcr.io/google_containers/hyperkube:v1.1.2"}
K8S_IMAGE_HYPERKUBE=${K8S_IMAGE_HYPERKUBE:-"guybrush/hyperkube:v1.2.0-alpha.3"}
# K8S_IMAGE_HYPERKUBE=${K8S_IMAGE_HYPERKUBE:-"guybrush/hyperkube:v1.1.2"}
K8S_IMAGE_ETCD=${K8S_IMAGE_ETCD:-"gcr.io/google_containers/etcd:2.2.1"}
K8S_IMAGE_FLANNEL=${K8S_IMAGE_FLANNEL:-"quay.io/coreos/flannel:0.5.3"}

################################################################################

main() {
  if [ "$1" == "init-ssl" ]; then
    verify_settings "init-ssl will overwrite ./ssl, are you sure? OK?" "$2"
    init_ssl
  elif [ "$1" == "kube-up" ]; then
    verify_settings "these are the settings you will deploy, OK?" "$2"
    kube_up_controller
    echo "wait for apiserver"
    wupio $K8S_CONTROLLER_IP 6443
    kube_up_workers
    install_k8s_addons
  elif [ "$1" == "kube-down" ]; then
    echo "kube-down: TODO.. currently everything is deleted in kube-up :)"
  elif [ "$1" == "kube-up-controller" ]; then
    verify_settings "these are the settings you will deploy, OK?" "$2"
    kube_up_controller
  elif [ "$1" == "kube-up-workers" ]; then
    verify_settings "these are the settings you will deploy, OK?" "$2"
    kube_up_workers
  elif [ "$1" == "install-kubectl" ]; then
    install_kubectl
  elif [ "$1" == "setup-kubectl" ]; then
    verify_settings "settings will be overwritten, OK?" "$2"
    setup_kubectl
  elif [ "$1" == "_kube-up-controller" ]; then
    #install_docker
    #install_docker_bootstrap
    install_k8s_controller "$2" "$3" "$4"
  elif [ "$1" == "_kube-up-worker" ]; then
    #install_docker
    #install_docker_bootstrap
    install_k8s_worker "$2" "$3" "$4"
  elif [ "$1" == "deploy-addons" ]; then
    install_k8s_addons
  else
    echo "$HELP"
  fi
}

################################################################################

verify_settings() {
  local msg=${1:-"OK?"}
  local yes=${2}
  declare -i max_user=4  # len("USER")
  declare -i max_ip=2    # len("IP")
  declare -i max_iface=5 # len("IFACE")

  local TMP0=($(echo $K8S_CONTROLLER | tr "/" " "))
  local TMP1=($(echo $TMP0           | tr "@" " "))
  K8S_CONTROLLER_USER=${TMP1[0]}
  K8S_CONTROLLER_IP=${TMP1[1]}
  K8S_CONTROLLER_IFACE=${TMP0[1]:-"eth0"}

  if [ ${#K8S_CONTROLLER_USER}  -gt $max_user  ]; then max_user=${#K8S_CONTROLLER_USER};   fi
  if [ ${#K8S_CONTROLLER_IP}    -gt $max_ip    ]; then max_ip=${#K8S_CONTROLLER_IP};       fi
  if [ ${#K8S_CONTROLLER_IFACE} -gt $max_iface ]; then max_iface=${#K8S_CONTROLLER_IFACE}; fi

  K8S_WORKER_IPS=""
  K8S_WORKER_USERS=""
  K8S_WORKER_IFACES=""

  for W in $K8S_WORKERS
  do
  {
    TMP0=($(echo $W    | tr "/" " "))
    TMP1=($(echo $TMP0 | tr "@" " "))
    K8S_WORKER_USERS=$K8S_WORKER_USERS" "${TMP1[0]}
    K8S_WORKER_IPS=$K8S_WORKER_IPS" "${TMP1[1]}
    K8S_WORKER_IFACES=$K8S_WORKER_IFACES" "${TMP0[1]:-"eth0"}
    if [ ${#TMP1[0]} -gt $max_user  ]; then max_user=${#TMP1[0]};  fi
    if [ ${#TMP1[1]} -gt $max_ip    ]; then max_ip=${#TMP1[1]};    fi
    if [ ${#TMP0[1]} -gt $max_iface ]; then max_iface=${#TMP0[1]}; fi
  }
  done

  K8S_WORKER_USERS=($K8S_WORKER_USERS)
  K8S_WORKER_IPS=($K8S_WORKER_IPS)
  K8S_WORKER_IFACES=($K8S_WORKER_IFACES)
  max_user=$max_user+1
  max_ip=$max_ip+1
  max_iface=$max_iface+1

  echo K8S_CONTROLLER=$K8S_CONTROLLER
  echo K8S_WORKERS=$K8S_WORKERS
  echo K8S_FLANNEL_NETWORK=$K8S_FLANNEL_NETWORK
  echo K8S_SERVICE_IP_RANGE=$K8S_SERVICE_IP_RANGE
  echo K8S_DNS_SERVICE_IP=$K8S_DNS_SERVICE_IP
  echo K8S_IMAGE_HYPERKUBE=$K8S_IMAGE_HYPERKUBE
  echo K8S_IMAGE_ETCD=$K8S_IMAGE_ETCD
  echo K8S_IMAGE_FLANNEL=$K8S_IMAGE_FLANNEL
  echo "------------------------------------------------"
  # print nice table of parsed values
  local layout="%-11s %-${max_user}s %-${max_ip}s %-${max_iface}s\n"
  printf "$layout" "TYPE" "USER" "IP" "IFACE"
  printf "$layout" "controller" ${K8S_CONTROLLER_USER} ${K8S_CONTROLLER_IP} ${K8S_CONTROLLER_IFACE}
  declare -i n=0
  for W in $K8S_WORKERS
  do
  {
    printf "$layout"  "worker$n" ${K8S_WORKER_USERS[$n]} ${K8S_WORKER_IPS[$n]} ${K8S_WORKER_IFACES[$n]}
    n=$n+1
  }
  done
  echo "------------------------------------------------"
  if [ "$2" != "-y" ]; then
    while true; do
      read -p "${msg} [yN]" yn
      # read -p "these are the settings you will deploy, OK? [yN]" yn
      case $yn in
          [Yy]* ) break;;
          [Nn]* ) exit;;
          # * ) echo "Please answer yes or no.";;
          * ) exit;;
      esac
    done
  fi
}

################################################################################

kube_up_controller() {
  echo "------------------------------------------------------------------------"
  echo "deploying controller: ${K8S_CONTROLLER_USER}@${K8S_CONTROLLER_IP}/${K8S_CONTROLLER_IFACE}"
  echo "------------------------------------------------------------------------"
  local machine="${K8S_CONTROLLER_USER}@${K8S_CONTROLLER_IP}"
  scp $PWD/k8s.sh ${machine}:~/k8s.sh
  scp $PWD/ssl/kube-controller-${K8S_CONTROLLER_IP}.tar ${machine}:~/ssl.tar
  CMD="sudo bash -c '\
mkdir -p /etc/kubernetes/ssl && \
tar -xf ./ssl.tar -C /etc/kubernetes/ssl && \
chmod +x ./k8s.sh && \
./k8s.sh _kube-up-controller ${K8S_CONTROLLER_IP} ${K8S_CONTROLLER_IFACE}
'"
  ssh ${machine} -t $CMD
}

################################################################################

kube_up_workers() {
  echo "waiting for kube-controller (apiserver) to be up and running"
  wupio $K8S_CONTROLLER_IP 6443
  declare -i n=0
  for w in $K8S_WORKERS
  do
  {
    machine_user=${K8S_WORKER_USERS[$n]}
    machine_iface=${K8S_WORKER_IFACES[$n]}
    machine_ip=${K8S_WORKER_IPS[$n]}
    machine="${machine_user}@${machine_ip}"
    echo "------------------------------------------------------------------------"
    echo "deploying worker: ${machine}/${machine_iface}"
    echo "------------------------------------------------------------------------"
    n=$n+1

    scp $PWD/k8s.sh ${machine}:~/k8s.sh
    scp $PWD/ssl/kube-worker-${machine_ip}.tar ${machine}:~/ssl.tar
    CMD="sudo bash -c '\
mkdir -p /etc/kubernetes/ssl && \
tar -xf ./ssl.tar -C /etc/kubernetes/ssl && \
chmod +x ./k8s.sh && \
./k8s.sh _kube-up-worker ${machine_ip} ${machine_iface} ${K8S_CONTROLLER_IP}
'"
    ssh ${machine} -t $CMD
  }
  done
}

################################################################################

install_docker() {
  apt-get update
  apt-get install -y git apt-transport-https

  apt-key adv --keyserver hkp://pgp.mit.edu:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D

  cat << EOF > /etc/apt/sources.list.d/docker.list
# Debian Wheezy
deb https://apt.dockerproject.org/repo debian-wheezy main
# Debian Jessie
deb https://apt.dockerproject.org/repo debian-jessie main
# Debian Stretch/Sid
deb https://apt.dockerproject.org/repo debian-stretch main
EOF

  apt-get update
  apt-get install -y docker-engine

  systemctl daemon-reload
  systemctl start docker
  systemctl enable docker
}

################################################################################

install_docker_bootstrap() {
  # sudo -b docker -d -H unix:///var/run/docker-bootstrap.sock \
  #  -p /var/run/docker-bootstrap.pid --iptables=false --ip-masq=false \
  #   --bridge=none --graph=/var/lib/docker-bootstrap 2> /var/log/docker-bootstrap.log 1> /dev/null

  cat <<EOF > /etc/systemd/system/docker-bootstrap.service
[Unit]
Description=docker-bootstrap for k8s-overlay-network via flannel
Documentation=https://docs.docker.com
After=network.target
# Requires=docker-bootstrap.socket

[Service]
Type=notify
ExecStart=/usr/bin/docker daemon \
  -H unix:///var/run/docker-bootstrap.sock \
  -p /var/run/docker-bootstrap.pid \
  --iptables=false \
  --ip-masq=false \
  --bridge=none \
  --graph=/var/lib/docker-bootstrap

MountFlags=slave
LimitNOFILE=1048576
LimitNPROC=1048576
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl start docker-bootstrap
  systemctl enable docker-bootstrap
}

################################################################################

install_k8s_controller() {
  local LOCAL_ADVERTISE_IP=$1
  local LOCAL_FLANNEL_IFACE=$2

  local containers=$(docker -H unix:///var/run/docker-bootstrap.sock ps -aq)
  if [[ ! -z  "$containers" ]]; then
    docker -H unix:///var/run/docker-bootstrap.sock stop $containers
    docker -H unix:///var/run/docker-bootstrap.sock rm $containers
  fi
  local containers=$(docker ps -aq)
  if [[ ! -z  "$containers" ]]; then
    docker stop $containers
    docker rm $containers
  fi


  # start etcd
  echo "------------------------------------------------------------------------"
  echo "starting etcd on docker-bootstrap"
  echo "------------------------------------------------------------------------"
  docker -H unix:///var/run/docker-bootstrap.sock run \
    --restart=always \
    --net=host \
    --name=etcd \
    -v /etc/kubernetes/ssl:/etc/kubernetes/ssl \
    -d \
    $K8S_IMAGE_ETCD \
    /usr/local/bin/etcd \
    --advertise-client-urls=https://localhost:4001,https://127.0.0.1:4001 \
    --listen-client-urls=https://0.0.0.0:4001 \
    --cert-file=/etc/kubernetes/ssl/kube-controller-cert.pem \
    --key-file=/etc/kubernetes/ssl/kube-controller-key.pem \
    --ca-file=/etc/kubernetes/ssl/kube-ca.pem \
    --data-dir=/var/etcd/data

  sleep 5

  # Set flannel net config
  echo "------------------------------------------------------------------------"
  echo "Set flannel net config"
  echo "------------------------------------------------------------------------"
  docker -H unix:///var/run/docker-bootstrap.sock run \
    --rm \
    --net=host \
    -v /etc/kubernetes/ssl:/etc/kubernetes/ssl \
    $K8S_IMAGE_ETCD \
    etcdctl -C https://127.0.0.1:4001 \
      --cert-file=/etc/kubernetes/ssl/kube-controller-cert.pem \
      --key-file=/etc/kubernetes/ssl/kube-controller-key.pem \
      --ca-file=/etc/kubernetes/ssl/kube-ca.pem \
      set /coreos.com/network/config \
        '{ "Network": "'${K8S_FLANNEL_NETWORK}'", "Backend": {"Type": "vxlan"}}'

  # start flannel
  echo "------------------------------------------------------------------------"
  echo "start flannel iface: $LOCAL_FLANNEL_IFACE"
  echo "------------------------------------------------------------------------"
  flannelCID=$(\
    docker -H unix:///var/run/docker-bootstrap.sock run \
      -d \
      --name=flannel \
      --restart=always \
      --net=host \
      --privileged \
      -v /dev/net:/dev/net \
      -v /etc/kubernetes/ssl:/etc/kubernetes/ssl \
      $K8S_IMAGE_FLANNEL \
      /opt/bin/flanneld \
      --etcd-endpoints=https://127.0.0.1:4001 \
      --etcd-keyfile=/etc/kubernetes/ssl/kube-controller-key.pem \
      --etcd-certfile=/etc/kubernetes/ssl/kube-controller-cert.pem \
      --etcd-cafile=/etc/kubernetes/ssl/kube-ca.pem \
      --iface="$LOCAL_FLANNEL_IFACE" )

  sleep 5

  # Copy flannel env out and source it on the host
  echo "------------------------------------------------------------------------"
  echo "Copy flannel env out and source it on the host"
  echo "------------------------------------------------------------------------"
  echo "flannelCID: ${flannelCID}"
  docker -H unix:///var/run/docker-bootstrap.sock cp ${flannelCID}:/run/flannel/subnet.env .
  source subnet.env

  DOCKER_CONF="/etc/default/docker"
  echo "DOCKER_OPTS=\"\$DOCKER_OPTS --mtu=${FLANNEL_MTU} --bip=${FLANNEL_SUBNET}\"" | sudo tee -a ${DOCKER_CONF}
  ifconfig docker0 down
  apt-get install -y bridge-utils
  brctl delbr docker0
  service docker restart

  sleep 5

mkdir -p /etc/kubernetes
  cat <<EOF > /etc/kubernetes/kube-config.yaml
apiVersion: v1
kind: Config
clusters:
- name: local
  cluster:
    certificate-authority: /etc/kubernetes/ssl/kube-ca.pem
    server: https://$K8S_CONTROLLER_IP:6443
users:
- name: kubelet
  user:
    client-certificate: /etc/kubernetes/ssl/kube-controller-cert.pem
    client-key: /etc/kubernetes/ssl/kube-controller-key.pem
contexts:
- context:
    cluster: local
    user: kubelet
  name: kubelet-context
current-context: kubelet-context
EOF
  
  cat <<EOF > /etc/kubernetes/etcd-config.json
{
  "cluster": {
    "machines": [ "https://127.0.0.1:4001" ]
  },
  "config": {
    "certFile": "/etc/kubernetes/ssl/kube-controller-cert.pem",
    "keyFile": "/etc/kubernetes/ssl/kube-controller-key.pem",
    "caCertFiles": [
      "/etc/kubernetes/ssl/kube-ca.pem"
    ],
    "timeout": 5000000000,
    "consistency": "WEAK"
  }
}
EOF

  echo "------------------------------------------------------------------------"
  echo "creating kube-manifest"
  echo "------------------------------------------------------------------------"
  mkdir -p /etc/kubernetes/manifests-custom
  # cat k8s_controller_manifest > /etc/kubernetes/manifests-custom/master.yml
  cat <<EOF > /etc/kubernetes/manifests-custom/master.yml
kind: Pod
apiVersion: v1
metadata:
  name: kube-controller
spec:
  hostNetwork: true
  containers:

  - name: kube-controller-manager
    image: ${K8S_IMAGE_HYPERKUBE}
    command:
    - /hyperkube
    - controller-manager
    - --master=http://127.0.0.1:8080
    - --service-account-private-key-file=/etc/kubernetes/ssl/kube-controller-key.pem
    - --root-ca-file=/etc/kubernetes/ssl/kube-ca.pem
    - --v=2
    livenessProbe:
      httpGet:
        host: 127.0.0.1
        path: /healthz
        port: 10252
      initialDelaySeconds: 15
      timeoutSeconds: 1
    volumeMounts:
    - mountPath: /etc/kubernetes/ssl
      name: ssl-certs-kubernetes
      readOnly: true
    - mountPath: /etc/ssl/certs
      name: ssl-certs-host
      readOnly: true

  - name: kube-apiserver
    image: ${K8S_IMAGE_HYPERKUBE}
    command:
    - /hyperkube
    - apiserver
    - --bind-address=0.0.0.0
    - --secure-port=6443
    - --etcd-config=/etc/kubernetes/etcd-config.json
    - --allow-privileged=true
    - --service-cluster-ip-range=${K8S_SERVICE_IP_RANGE}
    - --advertise-address=${LOCAL_ADVERTISE_IP}
    - --admission-control=NamespaceLifecycle,NamespaceExists,LimitRanger,SecurityContextDeny,ServiceAccount,ResourceQuota
    - --tls-cert-file=/etc/kubernetes/ssl/kube-controller-cert.pem
    - --tls-private-key-file=/etc/kubernetes/ssl/kube-controller-key.pem
    - --client-ca-file=/etc/kubernetes/ssl/kube-ca.pem
    - --service-account-key-file=/etc/kubernetes/ssl/kube-controller-key.pem
    - --v=2
    ports:
    - containerPort: 6443
      hostPort: 6443
      hostIP: 0.0.0.0
      name: https
    - containerPort: 8080
      hostPort: 8080
      hostIP: 127.0.0.1
      name: local
    volumeMounts:
    - mountPath: /etc/kubernetes/etcd-config.json
      name: etcd-config
      readOnly: true
    - mountPath: /etc/kubernetes/ssl
      name: ssl-certs-kubernetes
      readOnly: true
    - mountPath: /etc/ssl/certs
      name: ssl-certs-host
      readOnly: true

  - name: kube-scheduler
    image: ${K8S_IMAGE_HYPERKUBE}
    command:
    - /hyperkube
    - scheduler
    - --master=127.0.0.1:8080
    - --v=2

  volumes:
  - hostPath:
      path: /etc/kubernetes/etcd-config.json
    name: etcd-config
  - hostPath:
      path: /etc/kubernetes/ssl
    name: ssl-certs-kubernetes
  - hostPath:
      path: /usr/share/ca-certificates
    name: ssl-certs-host
EOF

  echo "------------------------------------------------------------------------"
  echo "Start kubelet & proxy, then start master components as pods"
  echo "------------------------------------------------------------------------"
  # Start kubelet & proxy, then start master components as pods
  # https://github.com/kubernetes/kubernetes/blob/master/docs/admin/kubelet.md
  docker run \
    -d \
    --name=kubelet \
    --net=host \
    --privileged \
    --restart=always \
    -v /sys:/sys:ro \
    -v /var/run:/var/run:rw \
    -v /:/rootfs:ro \
    -v /dev:/dev \
    -v /var/lib/docker/:/var/lib/docker:rw \
    -v /var/lib/kubelet/:/var/lib/kubelet:rw \
    -v /etc/kubernetes/manifests-custom:/etc/kubernetes/manifests-custom \
    ${K8S_IMAGE_HYPERKUBE} \
    /hyperkube kubelet \
    --containerized \
    --api-servers=http://127.0.0.1:8080 \
    --address=0.0.0.0 \
    --enable-server \
    --hostname-override=${LOCAL_ADVERTISE_IP} \
    --allow-privileged=true \
    --config=/etc/kubernetes/manifests-custom \
    --cluster-dns=${K8S_DNS_SERVICE_IP} \
    --cluster-domain=cluster.local \
    --v=2


  echo "------------------------------------------------------------------------"
  echo "Start kube-proxy"
  echo "------------------------------------------------------------------------"
  # https://github.com/kubernetes/kubernetes/blob/master/docs/admin/kube-proxy.md
  docker run \
    -d \
    --name=kube_proxy \
    --net=host \
    --privileged \
    --restart=always \
    -v /etc/ssl/certs:/usr/share/ca-certificates \
    ${K8S_IMAGE_HYPERKUBE} \
    /hyperkube proxy \
    --master=http://127.0.0.1:8080 \
    --v=2
}

################################################################################

install_k8s_worker() {
  local LOCAL_ADVERTISE_IP=$1
  local LOCAL_FLANNEL_IFACE=$2
  K8S_CONTROLLER_IP=$3 # TODO..

  local containers=$(docker -H unix:///var/run/docker-bootstrap.sock ps -aq)
  if [[ ! -z  "$containers" ]]; then
    docker -H unix:///var/run/docker-bootstrap.sock stop $containers
    docker -H unix:///var/run/docker-bootstrap.sock rm $containers
  fi
  local containers=$(docker ps -aq)
  if [[ ! -z  "$containers" ]]; then
    docker stop $containers
    docker rm $containers
  fi


  # start flannel
  echo "------------------------------------------------------------------------"
  echo "start flannel iface: $LOCAL_FLANNEL_IFACE"
  echo "------------------------------------------------------------------------"
  flannelCID=$(\
    docker -H unix:///var/run/docker-bootstrap.sock run \
      -d \
      --name=flannel \
      --restart=always \
      --net=host \
      --privileged \
      -v /dev/net:/dev/net \
      -v /etc/kubernetes/ssl:/etc/kubernetes/ssl \
      $K8S_IMAGE_FLANNEL \
      /opt/bin/flanneld \
      --etcd-endpoints=https://$K8S_CONTROLLER_IP:4001 \
      --etcd-keyfile=/etc/kubernetes/ssl/kube-worker-key.pem \
      --etcd-certfile=/etc/kubernetes/ssl/kube-worker-cert.pem \
      --etcd-cafile=/etc/kubernetes/ssl/kube-ca.pem \
      --iface="$LOCAL_FLANNEL_IFACE"\
  )

  sleep 5

  # Copy flannel env out and source it on the host
  echo "------------------------------------------------------------------------"
  echo "Copy flannel env out and source it on the host"
  echo "------------------------------------------------------------------------"
  echo "flannelCID: ${flannelCID}"
  docker -H unix:///var/run/docker-bootstrap.sock cp ${flannelCID}:/run/flannel/subnet.env .
  source subnet.env

  DOCKER_CONF="/etc/default/docker"
  echo "DOCKER_OPTS=\"\$DOCKER_OPTS --mtu=${FLANNEL_MTU} --bip=${FLANNEL_SUBNET}\"" | sudo tee -a ${DOCKER_CONF}
  ifconfig docker0 down
  apt-get install -y bridge-utils
  brctl delbr docker0
  service docker restart

  sleep 5

  mkdir -p /etc/kubernetes
  cat <<EOF > /etc/kubernetes/kube-config.yaml
apiVersion: v1
kind: Config
clusters:
- name: local
  cluster:
    certificate-authority: /etc/kubernetes/ssl/kube-ca.pem
    server: https://$K8S_CONTROLLER_IP:6443
users:
- name: kubelet
  user:
    client-certificate: /etc/kubernetes/ssl/kube-worker-cert.pem
    client-key: /etc/kubernetes/ssl/kube-worker-key.pem
contexts:
- context:
    cluster: local
    user: kubelet
  name: kubelet-context
current-context: kubelet-context
EOF

  # Start kubelet & proxy, then start master components as pods
  # https://github.com/kubernetes/kubernetes/blob/master/docs/admin/kubelet.md
  docker run \
    -d \
    --net=host \
    --privileged \
    --restart=always \
    -v /sys:/sys:ro \
    -v /var/run:/var/run:rw \
    -v /:/rootfs:ro \
    -v /dev:/dev \
    -v /var/lib/docker/:/var/lib/docker:rw \
    -v /var/lib/kubelet/:/var/lib/kubelet:rw \
    -v /etc/kubernetes/kube-config.yaml:/etc/kubernetes/kube-config.yaml:ro \
    -v /etc/kubernetes/ssl:/etc/kubernetes/ssl:ro \
    -v /etc/kubernetes/manifests-custom:/etc/kubernetes/manifests-custom \
    ${K8S_IMAGE_HYPERKUBE} \
    /hyperkube kubelet \
    --api-servers=https://$K8S_CONTROLLER_IP:6443 \
    --address=0.0.0.0 \
    --enable-server \
    --hostname-override=${LOCAL_ADVERTISE_IP} \
    --allow-privileged=true \
    --config=/etc/kubernetes/manifests-custom \
    --cluster-dns=${K8S_DNS_SERVICE_IP} \
    --cluster-domain=cluster.local \
    --tls-cert-file=/etc/kubernetes/ssl/kube-worker-cert.pem \
    --tls-private-key-file=/etc/kubernetes/ssl/kube-worker-key.pem \
    --kubeconfig=/etc/kubernetes/kube-config.yaml \
    --v=2

  # https://github.com/kubernetes/kubernetes/blob/master/docs/admin/kube-proxy.md
  docker run \
    -d \
    --net=host \
    --privileged \
    --restart=always \
    -v /etc/ssl/certs:/usr/share/ca-certificates \
    -v /etc/kubernetes/ssl:/etc/kubernetes/ssl \
    -v /etc/kubernetes/kube-config.yaml:/etc/kubernetes/kube-config.yaml \
    ${K8S_IMAGE_HYPERKUBE} \
    /hyperkube proxy \
    --master=https://$K8S_CONTROLLER_IP:6443 \
    --kubeconfig=/etc/kubernetes/kube-config.yaml \
    --v=2
}

################################################################################

install_kubectl() {
  # it would be cool to have kubectl inside hyperkube..
  # apt-get install -y curl
  local V="1.1.1"
  curl https://storage.googleapis.com/kubernetes-release/release/v$V/bin/linux/amd64/kubectl -o kubectl
  sudo mv kubectl /usr/local/bin/kubectl
  sudo chmod +x /usr/local/bin/kubectl
}

################################################################################

setup_kubectl() {
  KUBECTL=/usr/local/bin/kubectl

  $KUBECTL config set-cluster default \
    --server=https://$K8S_CONTROLLER_IP:6443 \
    --certificate-authority=`pwd`/ssl/kube-ca.pem

  $KUBECTL config set-credentials admin \
    --client-key=`pwd`/ssl/kube-admin-key.pem \
    --client-certificate=`pwd`/ssl/kube-admin-cert.pem

  $KUBECTL config set-context default \
    --cluster=default \
    --user=admin

  $KUBECTL config use-context default
}

################################################################################

install_k8s_addons() {
  # dns
  # registry
  # kubedash
  echo "------------------------------------------------------------------------"
  echo "install k8s-addons"
  echo "------------------------------------------------------------------------"
  KUBECTL=/usr/local/bin/kubectl
  cat <<EOF | $KUBECTL create -f -
apiVersion: v1
kind: Namespace
metadata:
  name: kube-system
EOF

  cat <<EOF | $KUBECTL create -f -
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: "KubeDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: $K8S_DNS_SERVICE_IP
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP

---

apiVersion: v1
kind: ReplicationController
metadata:
  name: kube-dns-v9
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    version: v9
    kubernetes.io/cluster-service: "true"
spec:
  replicas: 1
  selector:
    k8s-app: kube-dns
    version: v9
  template:
    metadata:
      labels:
        k8s-app: kube-dns
        version: v9
        kubernetes.io/cluster-service: "true"
    spec:
      containers:
      - name: etcd
        image: gcr.io/google_containers/etcd:2.0.9
        resources:
          limits:
            cpu: 100m
            memory: 50Mi
        command:
        - /usr/local/bin/etcd
        - -data-dir
        - /var/etcd/data
        - -listen-client-urls
        - http://127.0.0.1:2379,http://127.0.0.1:4001
        - -advertise-client-urls
        - http://127.0.0.1:2379,http://127.0.0.1:4001
        - -initial-cluster-token
        - skydns-etcd
        volumeMounts:
        - name: etcd-storage
          mountPath: /var/etcd/data
      - name: kube2sky
        image: gcr.io/google_containers/kube2sky:1.11
        resources:
          limits:
            cpu: 100m
            memory: 50Mi
        args:
        # command = "/kube2sky"
        - -domain=cluster.local
        - -kubecfg_file=/etc/kubernetes/kube-config.yaml
        volumeMounts:
        - name: etc-kubernetes
          mountPath: /etc/kubernetes 
      - name: skydns
        image: gcr.io/google_containers/skydns:2015-03-11-001
        resources:
          limits:
            cpu: 100m
            memory: 50Mi
        args:
        # command = "/skydns"
        - -machines=http://localhost:4001
        - -addr=0.0.0.0:53
        - -domain=cluster.local.
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 30
          timeoutSeconds: 5
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 1
          timeoutSeconds: 5
      - name: healthz
        image: gcr.io/google_containers/exechealthz:1.0
        resources:
          limits:
            cpu: 10m
            memory: 20Mi
        args:
        - -cmd=nslookup kubernetes.default.svc.cluster.local localhost >/dev/null
        - -port=8080
        ports:
        - containerPort: 8080
          protocol: TCP
      volumes:
      - name: etcd-storage
        emptyDir: {}
      - name: etc-kubernetes
        hostPath: 
          path: /etc/kubernetes
      dnsPolicy: Default
EOF

}


################################################################################
# https://github.com/coreos/coreos-kubernetes/tree/master/lib
# https://github.com/kubernetes/kubernetes/blob/172eab6/cluster/gce/util.sh#L478

init_ssl() {
  echo "------------------------------------------------------------------------"
  echo "init_ssl_ca"
  echo "------------------------------------------------------------------------"
  init_ssl_ca

  echo "------------------------------------------------------------------------"
  echo "init_ssl_key kube-admin kube-admin"
  echo "------------------------------------------------------------------------"
  init_ssl_key kube-admin kube-admin

  local controller_name="kube-controller"
  local controller_ip=${K8S_CONTROLLER_IP}
  local octets=($(echo "$K8S_SERVICE_IP_RANGE" | sed -e 's|/.*||' -e 's/\./ /g'))
  ((octets[3]+=1))
  local -r service_ip=$(echo "${octets[*]}" | sed 's/ /./g')
  local -r sans="IP.1=127.0.0.1,IP.2=${K8S_CONTROLLER_IP},IP.3=${service_ip},DNS.6=${controller_name}"

  echo "------------------------------------------------------------------------"
  echo "init_ssl_key kube-controller kube-controller-${controller_ip} ${sans}"
  echo "------------------------------------------------------------------------"
  init_ssl_key kube-controller kube-controller-${controller_ip} $sans

  local machine_user
  local machine_iface
  local machine_ip
  declare -i n=0
  for w in $K8S_WORKERS
  do
  {
    machine_user=${K8S_WORKER_USERS[$n]}
    machine_iface=${K8S_WORKER_IFACES[$n]}
    machine_ip=${K8S_WORKER_IPS[$n]}
    n=$n+1
    echo "------------------------------------------------------------------------"
    echo "init_ssl_key kube-worker kube-worker-${machine_ip} IP.1=127.0.0.1,IP.2=${machine_ip}"
    echo "------------------------------------------------------------------------"
    init_ssl_key kube-worker kube-worker-${machine_ip} "IP.1=127.0.0.1,IP.2=${machine_ip}"
  }
  done
}

################################################################################

init_ssl_ca() {
  OPENSSL=/usr/bin/openssl
  OUTDIR="./ssl"
  mkdir -p $OUTDIR

  $OPENSSL genrsa -out "$OUTDIR/kube-ca-key.pem" 2048
  $OPENSSL req -x509 -new -nodes -key "$OUTDIR/kube-ca-key.pem" \
    -days 10000 -out "$OUTDIR/kube-ca.pem" -subj "/CN=kube-ca"

  # $OPENSSL genrsa -out "$OUTDIR/flannel-etcd-ca-key.pem" 2048
  # $OPENSSL req -x509 -new -nodes -key "$OUTDIR/flannel-etcd-ca-key.pem" \
  #   -days 10000 -out "$OUTDIR/flannel-etcd-ca-key.pem" -subj "/CN=kube-flannel-etcd-ca"
}

################################################################################

init_ssl_key() {

  OPENSSL="/usr/bin/openssl"

  OUTDIR="./ssl"
  # CERTBASE="worker"
  # CN="kube-worker"
  #SANS=sans

  # OUTDIR="$1"   # "./ssl/"
  CERTBASE="$1" # "worker"
  CN="$2"       # "kube-worker"
  SANS="$3"     # "IP.1=127.0.0.1,IP.2=10.0.0.1"

  OUTFILE="$OUTDIR/$CN.tar"

  CNF_TEMPLATE="[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1=kubernetes
DNS.2=kubernetes.default
DNS.3=kubernetes.default.svc
DNS.4=kubernetes.default.svc.cluster
DNS.5=kubernetes.default.svc.cluster.local
"
  echo "Generating SSL artifacts in $OUTDIR"

  CONFIGFILE="$OUTDIR/$CERTBASE-req.cnf"
  CAFILE="$OUTDIR/kube-ca.pem"
  CAKEYFILE="$OUTDIR/kube-ca-key.pem"
  KEYFILE="$OUTDIR/$CERTBASE-key.pem"
  CSRFILE="$OUTDIR/$CERTBASE.csr"
  PEMFILE="$OUTDIR/$CERTBASE-cert.pem"

  CONTENTS="${CAFILE} ${KEYFILE} ${PEMFILE}"

  # Add SANs to openssl config
  echo "$CNF_TEMPLATE$(echo $SANS | tr ',' '\n')" > "$CONFIGFILE"

  # echo $SANS
  # cat $CONFIGFILE

  $OPENSSL genrsa -out "$KEYFILE" 2048
  $OPENSSL req -new -key "$KEYFILE" -out "$CSRFILE" -subj "/CN=$CN" -config "$CONFIGFILE"
  $OPENSSL x509 -req -in "$CSRFILE" -CA "$CAFILE" -CAkey "$CAKEYFILE" -CAcreateserial -out "$PEMFILE" -days 365 -extensions v3_req -extfile "$CONFIGFILE"

  tar -cf $OUTFILE -C $OUTDIR $(for  f in $CONTENTS;do printf "$(basename $f) ";done)

  echo "Bundled SSL artifacts into $OUTFILE"
  echo "$CONTENTS"
}

################################################################################

wupio() {
  # [w]ait [u]ntil [p]ort [i]s [o]pen
  # $1 .. ip
  # $2 .. port
  [ -n "$1" ] && [ -n "$2" ] && \
    until nc -z ${1} ${2}; do sleep 1 && echo -n .; done;
  echo ""
}

################################################################################

main $1 $2 $3 $4
