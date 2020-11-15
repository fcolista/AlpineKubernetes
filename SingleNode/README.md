# Build a Single Node Kubernetes "Cluster" based on Alpine Linux

## Prerequists

- A node (VM) with the latest Alpine Linux (3.12.1)
- SSH and root (sudo) access to the node
- The name of the node in an enviroment variable NODE_NAME
- The ip of the node in an environment variable NODE_IP
- The network/CIDR of the node in an environment variable NODE_NET

Here we use:
| NODE_NAME | NODE_IP       | NODE_NET        |
|-----------|---------------|-----------------|
| kube01    | 192.168.10.10 | 192.168.10.0/24 | 

## Prepare the Node

Login to the node a become root:
```
ssh vagrant@kube01
sudo su -
```
Set the environment variables used in scripts:
```
export NODE_NAME="kube01"
export NODE_IP="192.168.10.10"
export NODE_NET="192.168.10.0/24"
```
Enable edge testing repositories:
```
cat >>/etc/apk/repositories << EOF
http://nl.alpinelinux.org/alpine/edge/main
http://nl.alpinelinux.org/alpine/edge/community
http://nl.alpinelinux.org/alpine/edge/testing
EOF
```
Disable swap by remove the swap line from /etc/fstab:
```
UUID=xxxxxxxxxxxxxxxxxx	swap	swap	defaults	0 0
```
Set the number of openfiles to a higher value:
```
cat >> /etc/rc.conf << EOF
rc_ulimit="-n 16384" 
EOF
```
Enable IP forwarding and config a conntrack setting:
```
cat >> /etc/sysctl.conf << EOF
net.ipv4.ip_forward=1
net.netfilter.nf_conntrack_tcp_be_liberal=1
EOF
```
Add the packages for Containerd, ETCD and Kubernetes 
```
apk update
apk upgrade
apk add containerd etcd etcd-ctl
apk add kubernetes kube-apiserver kube-controller-manager kube-scheduler kube-proxy kubelet kubectl
apk add socat util-linux conntrack-tools nfs-utils findutils coreutils openssl
```
Containerd does not come with a init script, so create it:
```
mkdir -p /etc/containerd
mkdir -p /var/log/containerd
cat > /etc/init.d/containerd << EOF
#!/sbin/openrc-run
description="Containerd container service"
pidfile=\${pidfile:-"/run/\${SVCNAME}.pid"}
user=\${user:-root}
group=\${group:-root}
command="/usr/bin/containerd"
command_args="\${command_args}"
command_background="true"
start_stop_daemon_args="--user \${user} --group \${group} \
	--stdout /var/log/\${SVCNAME}/\${SVCNAME}.log \
	--stderr /var/log/\${SVCNAME}/\${SVCNAME}.log"
depend() {
	after net
}
EOF
chmod +x /etc/init.d/containerd
```
Copy the CNI plugins to a location where the pod-network and kubelet can vind them:
```
mkdir -p /opt/cni/bin
cp -a /usr/libexec/cni/. /opt/cni/bin
```
Active the deamons after a reboot:
```
rc-update add cgroups
rc-update add containerd
rc-update add etcd
rc-update add kube-apiserver 
rc-update add kube-controller-manager 
rc-update add kube-scheduler
rc-update add kube-proxy 
rc-update add kubelet
```
## Make the kubernetes certs on this node:
```
cd /etc/kubernetes
cat > openssl-apiserver.cnf << EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
IP.1 = 10.96.0.1
IP.2 = ${NODE_IP}
IP.3 = 127.0.0.1
EOF
cat > openssl-${NODE_NAME}.cnf << EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${NODE_NAME}
IP.1 = ${NODE_IP}
EOF
openssl genrsa -out ca.key 2048
openssl req -new -key ca.key -subj "/CN=KUBERNETES-CA" -out ca.csr
openssl x509 -req -in ca.csr -signkey ca.key -CAcreateserial  -out ca.crt -days 10000
openssl genrsa -out kube-apiserver.key 2048
openssl req -new -key kube-apiserver.key -subj "/CN=kube-apiserver" -out kube-apiserver.csr -config openssl-apiserver.cnf
openssl x509 -req -in kube-apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out kube-apiserver.crt -extensions v3_req -extfile openssl-apiserver.cnf -days 10000
openssl genrsa -out kube-scheduler.key 2048
openssl req -new -key kube-scheduler.key -subj "/CN=system:kube-scheduler" -out kube-scheduler.csr
openssl x509 -req -in kube-scheduler.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out kube-scheduler.crt -days 10000
openssl genrsa -out kube-controller-manager.key 2048
openssl req -new -key kube-controller-manager.key -subj "/CN=system:kube-controller-manager" -out kube-controller-manager.csr
openssl x509 -req -in kube-controller-manager.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out kube-controller-manager.crt -days 10000
openssl genrsa -out kube-proxy.key 2048
openssl req -new -key kube-proxy.key -subj "/CN=system:kube-proxy" -out kube-proxy.csr
openssl x509 -req -in kube-proxy.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out kube-proxy.crt -days 10000
openssl genrsa -out ${NODE_NAME}.key 2048
openssl req -new -key ${NODE_NAME}.key -subj "/CN=system:node:${NODE_NAME}/O=system:nodes" -out ${NODE_NAME}.csr -config openssl-${NODE_NAME}.cnf
openssl x509 -req -in ${NODE_NAME}.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out ${NODE_NAME}.crt -extensions v3_req -extfile openssl-${NODE_NAME}.cnf -days 10000
openssl genrsa -out admin.key 2048
openssl req -new -key admin.key -subj "/CN=admin/O=system:masters" -out admin.csr
openssl x509 -req -in admin.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out admin.crt -days 10000
openssl genrsa -out service-account.key 2048
openssl req -new -key service-account.key -subj "/CN=service-accounts" -out service-account.csr
openssl x509 -req -in service-account.csr -CA ca.crt -CAkey ca.key -CAcreateserial  -out service-account.crt -days 10000
export ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)
cat > /etc/kubernetes/encryption-config.yaml << EOF
kind: EncryptionConfig
apiVersion: v1
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=admin.kubeconfig
kubectl config set-credentials admin \
    --client-certificate=admin.crt \
    --client-key=admin.key \
    --embed-certs=true \
    --kubeconfig=admin.kubeconfig
kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=admin \
    --kubeconfig=admin.kubeconfig
kubectl config use-context default --kubeconfig=admin.kubeconfig
kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-scheduler.kubeconfig
kubectl config set-credentials system:kube-scheduler \
    --client-certificate=kube-scheduler.crt \
    --client-key=kube-scheduler.key \
    --embed-certs=true \
    --kubeconfig=kube-scheduler.kubeconfig
kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-scheduler \
    --kubeconfig=kube-scheduler.kubeconfig
kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig
kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://127.0.0.1:6443 \
    --kubeconfig=kube-controller-manager.kubeconfig
kubectl config set-credentials system:kube-controller-manager \
    --client-certificate=kube-controller-manager.crt \
    --client-key=kube-controller-manager.key \
    --embed-certs=true \
    --kubeconfig=kube-controller-manager.kubeconfig
kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-controller-manager \
    --kubeconfig=kube-controller-manager.kubeconfig
kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig
kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://${NODE_IP}:6443 \
    --kubeconfig=kube-proxy.kubeconfig
kubectl config set-credentials system:kube-proxy \
    --client-certificate=kube-proxy.crt \
    --client-key=kube-proxy.key \
    --embed-certs=true \
    --kubeconfig=kube-proxy.kubeconfig
kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:kube-proxy \
    --kubeconfig=kube-proxy.kubeconfig
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig
kubectl config set-cluster kubernetes-the-hard-way \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server=https://${NODE_IP}:6443 \
    --kubeconfig=${NODE_NAME}.kubeconfig
kubectl config set-credentials system:node:${NODE_NAME} \
    --client-certificate=${NODE_NAME}.crt \
    --client-key=${NODE_NAME}.key \
    --embed-certs=true \
    --kubeconfig=${NODE_NAME}.kubeconfig
kubectl config set-context default \
    --cluster=kubernetes-the-hard-way \
    --user=system:node:${NODE_NAME} \
    --kubeconfig=${NODE_NAME}.kubeconfig
kubectl config use-context default --kubeconfig=${NODE_NAME}.kubeconfig
cat > /etc/conf.d/kube-apiserver << EOF
command_args="--advertise-address=${NODE_IP} \
  --allow-privileged=true \
  --apiserver-count=2 \
  --audit-log-maxage=30 \
  --audit-log-maxbackup=3 \
  --audit-log-maxsize=100 \
  --audit-log-path=/var/log/audit.log \
  --authorization-mode=Node,RBAC \
  --bind-address=0.0.0.0 \
  --client-ca-file=/etc/kubernetes/ca.crt \
  --enable-admission-plugins=NodeRestriction,ServiceAccount \
  --enable-swagger-ui=true \
  --enable-bootstrap-token-auth=true \
  --etcd-servers=http://127.0.0.1:2379 \
  --event-ttl=1h \
  --encryption-provider-config=/etc/kubernetes/encryption-config.yaml \
  --kubelet-certificate-authority=/etc/kubernetes/ca.crt \
  --kubelet-client-certificate=/etc/kubernetes/kube-apiserver.crt \
  --kubelet-client-key=/etc/kubernetes/kube-apiserver.key \
  --kubelet-https=true \
  --runtime-config=api/all=true \
  --service-account-key-file=/etc/kubernetes/service-account.crt \
  --service-cluster-ip-range=10.96.0.0/24 \
  --service-node-port-range=30000-32767 \
  --tls-cert-file=/etc/kubernetes/kube-apiserver.crt \
  --tls-private-key-file=/etc/kubernetes/kube-apiserver.key \
  --enable-aggregator-routing=true \
  --v=2"
EOF
cat > /etc/conf.d/kube-scheduler << EOF
command_args="--kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
  --address=127.0.0.1 \
  --leader-elect=true \
  --v=2"
EOF
cat > /etc/conf.d/kube-controller-manager << EOF
 command_args="--bind-address=127.0.0.1 \
  --cluster-cidr=10.0.0.0/16 \
  --allocate-node-cidrs \
  --cluster-name=kubernetes \
  --cluster-signing-cert-file=/etc/kubernetes/ca.crt \
  --cluster-signing-key-file=/etc/kubernetes/ca.key \
  --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
  --leader-elect=true \
  --root-ca-file=/etc/kubernetes/ca.crt \
  --service-account-private-key-file=/etc/kubernetes/service-account.key \
  --service-cluster-ip-range=10.96.0.0/24 \
  --use-service-account-credentials=true \
  --v=2"
EOF
cat > /etc/conf.d/kube-proxy << EOF
command_args="--config=/var/lib/kube-proxy/kube-proxy-config.yaml"
EOF
cat > /var/lib/kube-proxy/kube-proxy-config.yaml << EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/etc/kubernetes/kube-proxy.kubeconfig"
mode: "iptables"
clusterCIDR: "${NODE_NET}"
EOF
cat > /etc/conf.d/kubelet << EOF
command_args="--config=/var/lib/kubelet/kubelet-config.yaml \
  --image-pull-progress-deadline=2m \
  --kubeconfig=/etc/kubernetes/${NODE_NAME}.kubeconfig \
  --tls-cert-file=/etc/kubernetes/${NODE_NAME}.crt \
  --tls-private-key-file=/etc/kubernetes/${NODE_NAME}.key \
  --network-plugin=cni \
  --register-node=true \
  --container-runtime=remote \
  --runtime-request-timeout=15m \
  --container-runtime-endpoint=unix:///run/containerd/containerd.sock \
  --v=2"
EOF
cat > /var/lib/kubelet/kubelet-config.yaml << EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/etc/kubernetes/ca.crt"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.96.0.10"
resolvConf: "/etc/resolv.conf"
runtimeRequestTimeout: "15m"
EOF
```
Clean up:
```
cd /etc/kubernetes
rm *.csr
rm *.srl
```
Reboot:
```
reboot
```
