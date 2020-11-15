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
Install containerd and Kubernetes base package:
```
apk update
apk add containerd kubernetes
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
rc-update add cgroups
rc-update add containerd
```
Add the kubernetes process that need to run on master and nodes

```
apk add kube-proxy kubelet
apk add socat util-linux conntrack-tools nfs-utils findutils coreutils
rc-update add kube-proxy 
rc-update add kubele
```
Fix path of CNI needed by pod-network (weave):
```
mkdir -p /opt/cni/bin
cp -a /usr/libexec/cni/. /opt/cni/bin
```
