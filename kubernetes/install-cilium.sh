cilium install --version 1.18.1 \
  --set kubeProxyReplacement=true \
  --set bgpControlPlane.enabled=true \
  --set ipam.mode=kubernetes \
  --set cni.binPath=/usr/libexec/cni
