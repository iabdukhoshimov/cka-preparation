# Troubleshooting solutions

Try each scenario for at least 10 minutes before reading. The method matters more than the fix:

```
kubectl get nodes / get pods -A          # what's unhealthy?
kubectl describe <obj>                   # Events at the bottom
kubectl logs <pod> [-p]                  # app / previous crash
ssh node -> systemctl status kubelet; journalctl -u kubelet -e
ssh node -> crictl ps -a; crictl logs <id>   # when the API server itself is down
ls /etc/kubernetes/manifests             # static pods (control plane)
```

<details><summary>1. Pods Pending: scheduler</summary>

`kubectl -n kube-system get pods` shows `kube-scheduler-*` in CrashLoopBackOff (or missing). `kubectl -n kube-system logs kube-scheduler-cka-control-plane` → `exec: "kube-schedular": executable file not found`.
Fix on the control plane: `vim /etc/kubernetes/manifests/kube-scheduler.yaml` → `- kube-scheduler`. The kubelet recreates the static pod automatically.
</details>

<details><summary>2. Worker NotReady: kubelet stopped</summary>

`./cluster/ssh.sh w2` → `systemctl status kubelet` (inactive, disabled) → `systemctl enable --now kubelet`.
</details>

<details><summary>3. Worker NotReady: kubelet config</summary>

`journalctl -u kubelet -e` → `unable to load client CA file /etc/kubernetes/pki/ca-cert.crt`.
Fix `clientCAFile: /etc/kubernetes/pki/ca.crt` in `/var/lib/kubelet/config.yaml`, then `systemctl restart kubelet`.
Know these paths: `/var/lib/kubelet/config.yaml`, `/etc/kubernetes/kubelet.conf`, `/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf` (kind: `/etc/systemd/system/kubelet.service.d/`).
</details>

<details><summary>4. API server down</summary>

kubectl fails, so go to the node: `crictl ps -a | grep apiserver` → `crictl logs <id>` → etcd connection refused on `127.0.0.1:2381`.
Fix `--etcd-servers=https://127.0.0.1:2379` in `/etc/kubernetes/manifests/kube-apiserver.yaml`. It takes about a minute to come back (`watch crictl ps`).
</details>

<details><summary>5. Service returns nothing: two bugs</summary>

`kubectl -n ts5 get endpointslices` → no endpoints: selector `app=webapp` but pods are `app=web`. `kubectl -n ts5 edit svc web` → selector `app: web`.
Then the targetPort is 8080, but nginx listens on 80 → set `targetPort: 80`.
</details>

<details><summary>6. DNS broken</summary>

`kubectl -n kube-system get pods -l k8s-app=kube-dns` → ImagePullBackOff. Check the tag from another node or `kubectl -n kube-system rollout history deploy coredns`, then `kubectl -n kube-system rollout undo deploy coredns`.
</details>

<details><summary>7. NetworkPolicy</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-frontend, namespace: ts7}
spec:
  podSelector: {matchLabels: {app: backend}}
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector: {matchLabels: {app: frontend}}
    ports:
    - {protocol: TCP, port: 80}
```
Policies are additive (OR'ed), so default-deny stays in place.
</details>

<details><summary>8. No pods from Deployment: controller-manager</summary>

A Deployment exists but no ReplicaSet/pods → the controller-manager is the suspect. Its logs show `stat /etc/kubernetes/controller-manager.config: no such file`. Fix `--kubeconfig=/etc/kubernetes/controller-manager.conf`.
</details>

<details><summary>9. PVC Pending</summary>

`kubectl -n ts9 describe pvc db-data` → `storageclass "fast-ssd" not found`. `storageClassName` is immutable on a PVC, so:
`kubectl -n ts9 get pvc db-data -o yaml > pvc.yaml`, set `storageClassName: standard`, then delete pod + PVC and recreate both.
Note: kind's `standard` class is `WaitForFirstConsumer`, so the PVC stays Pending until the pod is scheduled. That's normal.
</details>

<details><summary>10. Deployment never Available: two bugs</summary>

1. `describe pod` → `FailedScheduling: Insufficient cpu` (requests 50 CPUs). Lower it to `50m`.
2. Then `CreateContainerConfigError: couldn't find key DATABASE_HOST in ConfigMap` → key should be `DB_HOST`.

`kubectl -n ts10 edit deploy api` fixes both at once.
</details>

**Reset everything:** `./cluster/down.sh && ./cluster/up.sh`
