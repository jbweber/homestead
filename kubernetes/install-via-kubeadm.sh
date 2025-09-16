sudo kubeadm init --pod-network-cidr=10.100.0.0/20 --service-cidr=10.100.16.0/20 --skip-phases=addon/kube-proxy > kubeadm-$(date +%s).log 2>&1

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true
