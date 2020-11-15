# Build a Single Node Kubernetes "Cluster" based on Alpine Linux

## Prerequists

A node (VM) with Alpine Linux (3.12.1) with ssh and root (sudo) access

## Prepare the Node

Login to the node a become root:
```
ssh user@node
sudo su -
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
apk add containerd etcd etcd-ctl
apk add kubernetes kube-apiserver kube-controller-manager kube-scheduler kube-proxy kubelet kubectl
apk add socat util-linux conntrack-tools nfs-utils findutils coreutils
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
