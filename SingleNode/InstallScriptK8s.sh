mkdir /run/flannel
cat > /run/flannel/subnet.env << EOF
FLANNEL_NETWORK=10.100.0.0/16
FLANNEL_SUBNET=10.100.1.1/24
FLANNEL_MTU=1450
FLANNEL_IPMASQ=true
EOF
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
cat > apiserver-clusterrole-binding.yaml << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kube-apiserver
EOF
cat > apiserver-clusterrole.yaml << EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF
kubectl apply -f apiserver-clusterrole.yaml
kubectl apply -f apiserver-clusterrole-binding.yaml
kubectl apply -f https://raw.githubusercontent.com/alainvanhoof/AlpineKubernetes/main/SingleNode/dns-coredns.yml
