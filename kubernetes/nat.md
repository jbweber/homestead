# KubeVirt VM Floating IP with BGP and 1:1 NAT

This guide shows how to create a floating IP for a KubeVirt VM that is announced via BGP and provides 1:1 NAT for all protocols including ICMP/ping.

## Prerequisites

- Kubernetes cluster with Cilium CNI
- Cilium BGP control plane enabled and peering established
- KubeVirt VM running with the label `vm.kubevirt.io/name: test-vm`
- Privileged containers allowed (for NAT setup)

## Architecture Overview

This setup creates:
1. **BGP Advertisement**: Announces the floating IP via BGP to your network
2. **LoadBalancer Service**: Provides the floating IP assignment and BGP trigger
3. **1:1 NAT DaemonSet**: Handles all traffic forwarding between floating IP and VM

## Step-by-Step Setup

### Step 1: Get VM Pod IP

```bash
VM_POD_IP=$(kubectl get pods -l vm.kubevirt.io/name=test-vm -o jsonpath='{.items[0].status.podIP}')
echo "VM Pod IP: $VM_POD_IP"
```

### Step 2: Create BGP Advertisement Policy

This tells Cilium to announce LoadBalancer services with the `announce-bgp: "true"` label:

```bash
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumBGPAdvertisement
metadata:
  name: loadbalancer-advertisement
  labels:
    advertise: bgp  # Must match your BGP peer config
spec:
  advertisements:
  - advertisementType: "Service"
    service:
      addresses:
      - "ExternalIP"
    selector:
      matchLabels:
        announce-bgp: "true"
EOF
```

### Step 3: Create LoadBalancer Service

This service targets your VM and gets the floating IP:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: vm-floating-ip
  labels:
    announce-bgp: "true"  # Matches BGP advertisement selector
spec:
  type: LoadBalancer
  externalIPs:
  - "192.168.100.10"  # Your desired floating IP
  selector:
    vm.kubevirt.io/name: test-vm  # Targets your VM
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
EOF
```

### Step 4: Create 1:1 NAT DaemonSet

**Important**: Replace `VM_POD_IP_HERE` with the actual IP from Step 1.

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: vm-floating-ip-nat
  labels:
    app: vm-floating-ip-nat
spec:
  selector:
    matchLabels:
      app: vm-floating-ip-nat
  template:
    metadata:
      labels:
        app: vm-floating-ip-nat
    spec:
      hostNetwork: true
      tolerations:
      - operator: Exists
      containers:
      - name: nat-manager
        image: alpine:latest
        command: ["/bin/sh"]
        args:
        - -c
        - |
          apk add --no-cache iptables
          
          # Enable IP forwarding
          echo 1 > /proc/sys/net/ipv4/ip_forward
          
          # Wait for network to stabilize
          sleep 10
          
          VM_IP="VM_POD_IP_HERE"  # Replace with actual VM pod IP
          FLOATING_IP="192.168.100.10"
          
          echo "Setting up 1:1 NAT: \$FLOATING_IP <-> \$VM_IP"
          
          # DNAT: All incoming traffic to floating IP -> VM
          iptables -t nat -I PREROUTING -d \$FLOATING_IP -j DNAT --to-destination \$VM_IP
          
          # SNAT: All outgoing traffic from VM -> floating IP
          iptables -t nat -I POSTROUTING -s \$VM_IP -j SNAT --to-source \$FLOATING_IP
          
          echo "1:1 NAT setup complete: \$FLOATING_IP <-> \$VM_IP"
          
          # Monitor and maintain rules
          while true; do
            sleep 60
            # Re-add rules if they disappear
            if ! iptables -t nat -C PREROUTING -d \$FLOATING_IP -j DNAT --to-destination \$VM_IP 2>/dev/null; then
              echo "Re-adding DNAT rule"
              iptables -t nat -I PREROUTING -d \$FLOATING_IP -j DNAT --to-destination \$VM_IP
            fi
            if ! iptables -t nat -C POSTROUTING -s \$VM_IP -j SNAT --to-source \$FLOATING_IP 2>/dev/null; then
              echo "Re-adding SNAT rule"
              iptables -t nat -I POSTROUTING -s \$VM_IP -j SNAT --to-source \$FLOATING_IP
            fi
          done
        securityContext:
          privileged: true
        volumeMounts:
        - name: proc
          mountPath: /proc
        - name: sys
          mountPath: /sys
      volumes:
      - name: proc
        hostPath:
          path: /proc
      - name: sys
        hostPath:
          path: /sys
EOF
```

## Verification Steps

### 1. Check Service Status

```bash
# Verify service has external IP and endpoints
kubectl get service vm-floating-ip -o wide
kubectl get endpoints vm-floating-ip
```

Expected output:
```
NAME             TYPE           EXTERNAL-IP      PORT(S)        
vm-floating-ip   LoadBalancer   192.168.100.10   80:XXXXX/TCP   

NAME             ENDPOINTS         
vm-floating-ip   10.100.1.211:80   
```

### 2. Check BGP Advertisement

```bash
# Verify route is announced via BGP
kubectl exec -n kube-system ds/cilium -- cilium bgp routes | grep 192.168.100.10

# Check route count increased
kubectl get ciliumbgpnodeconfig -o yaml | grep -A 3 routeCount
```

### 3. Check NAT Setup

```bash
# Verify NAT pods are running
kubectl get pods -l app=vm-floating-ip-nat -o wide

# Check NAT logs
kubectl logs -l app=vm-floating-ip-nat --tail=20
```

### 4. Test Connectivity

```bash
# Test ping (ICMP) - should work through NAT
ping 192.168.100.10

# Test SSH (if enabled in VM)
ssh user@192.168.100.10

# Test HTTP (if web server running in VM)
curl http://192.168.100.10

# Compare with direct VM access
ping 10.100.1.211  # Direct VM IP
```

## How It Works

1. **BGP Advertisement**: Cilium announces `192.168.100.10/32` to your BGP peers
2. **Traffic Ingress**: External traffic to `192.168.100.10` arrives at your cluster nodes
3. **DNAT**: iptables PREROUTING rule forwards traffic from `192.168.100.10` to VM pod IP
4. **Traffic Processing**: VM processes the traffic normally
5. **SNAT**: iptables POSTROUTING rule makes VM's outbound traffic appear from `192.168.100.10`

## Supported Protocols

This setup supports **all IP protocols**:
- TCP (HTTP, SSH, etc.)
- UDP (DNS, etc.) 
- ICMP (ping, traceroute)
- Any other IP protocol

## Cleanup

To remove the setup:

```bash
kubectl delete service vm-floating-ip
kubectl delete ciliumbgpadvertisement loadbalancer-advertisement
kubectl delete daemonset vm-floating-ip-nat
```

## Troubleshooting

### BGP Route Not Announced
- Check if service has `announce-bgp: "true"` label
- Verify BGP advertisement has correct `advertise: bgp` label
- Ensure service has endpoints (VM pod must be running)

### Ping Not Working
- Check NAT daemonset logs: `kubectl logs -l app=vm-floating-ip-nat`
- Verify iptables rules are installed on all nodes
- Ensure VM pod can respond to ping

### Service Pending External IP
- Check if `externalIPs` is set correctly in service spec
- LoadBalancer IPAM pools may not be working - use `externalIPs` instead

## Notes

- Replace `192.168.100.10` with your desired floating IP
- Replace `test-vm` with your actual VM name
- The setup requires privileged containers for NAT functionality
- NAT rules are maintained automatically by the DaemonSet

This creates a true floating IP experience similar to OpenStack floating IPs or AWS Elastic IPs!