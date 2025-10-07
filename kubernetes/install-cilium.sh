cilium install --version 1.18.2 \
  --set kubeProxyReplacement=true \
  --set bgpControlPlane.enabled=true \
  --set ipam.mode=kubernetes \
  --set cni.binPath=/usr/libexec/cni \
  --set cni.exclusive=true

 # kubectl apply -f https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/master/deployments/multus-daemonset-thick.yml