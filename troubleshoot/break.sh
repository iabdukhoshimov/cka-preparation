#!/usr/bin/env bash
# Break the cluster on purpose. Fix it yourself, then verify with ./troubleshoot/check.sh <n>.
#   ./troubleshoot/break.sh list
#   ./troubleshoot/break.sh 3
# Solutions: troubleshoot/SOLUTIONS.md (don't peek before trying ~10 min).
set -euo pipefail

CP=cka-control-plane; W1=cka-worker; W2=cka-worker2
node() { docker exec "$1" bash -c "$2"; }
ns()   { kubectl create ns "$1" --dry-run=client -o yaml | kubectl apply -f - >/dev/null; }

case "${1:-list}" in
list)
  cat <<'EOF'
 1  New pods in namespace ts1 stay Pending forever.
 2  Node cka-worker2 is NotReady.
 3  Node cka-worker is NotReady (and restarting kubelet doesn't help).
 4  kubectl can't reach the API server at all.
 5  Service "web" in ts5 returns nothing / connection refused.
 6  Pods can't resolve DNS names.
 7  NetworkPolicy: allow ONLY pod "frontend" to reach pod "backend" on port 80 in ts7.
 8  Deployment "late" in ts8 exists but no pods are ever created.
 9  Pod "db" in ts9 is Pending.
10  Deployment "api" in ts10 never becomes Available.
EOF
  ;;
1)
  node $CP "sed -i 's/^    - kube-scheduler$/    - kube-schedular/' /etc/kubernetes/manifests/kube-scheduler.yaml"
  ns ts1; kubectl -n ts1 create deploy app --image=nginx --replicas=2
  echo "Broken: scheduling. Make deployment ts1/app Available." ;;
2)
  node $W2 "systemctl stop kubelet; systemctl disable kubelet" 2>/dev/null
  echo "Broken: cka-worker2 (wait ~40s for NotReady). Make it Ready." ;;
3)
  node $W1 "sed -i 's#clientCAFile: .*#clientCAFile: /etc/kubernetes/pki/ca-cert.crt#' /var/lib/kubelet/config.yaml; systemctl restart kubelet"
  echo "Broken: cka-worker (wait ~50s for NotReady). Make it Ready." ;;
4)
  node $CP "sed -i 's#--etcd-servers=https://127.0.0.1:2379#--etcd-servers=https://127.0.0.1:2381#' /etc/kubernetes/manifests/kube-apiserver.yaml"
  echo "Broken: API server. Hint: you'll need ./cluster/ssh.sh cp + crictl." ;;
5)
  ns ts5
  kubectl -n ts5 create deploy web --image=nginx --replicas=2
  kubectl -n ts5 create svc clusterip web --tcp=80:8080 --dry-run=client -o yaml \
    | sed 's/app: web/app: webapp/' | kubectl apply -f -
  echo "Broken: ts5/web. 'kubectl -n ts5 run t --rm -it --image=busybox -- wget -qO- web' should print nginx HTML." ;;
6)
  kubectl -n kube-system set image deploy/coredns coredns=registry.k8s.io/coredns/coredns:v1.99.0
  echo "Broken: cluster DNS." ;;
7)
  ns ts7
  kubectl -n ts7 run backend  --image=nginx --labels=app=backend
  kubectl -n ts7 run frontend --image=busybox --labels=app=frontend -- sleep 1d
  kubectl -n ts7 run other    --image=busybox --labels=app=other -- sleep 1d
  kubectl -n ts7 expose pod backend --port=80
  kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny, namespace: ts7}
spec: {podSelector: {}, policyTypes: [Ingress]}
EOF
  echo "Task: keep default-deny, add a policy so ONLY frontend reaches backend:80. 'other' must stay blocked." ;;
8)
  node $CP "sed -i 's#--kubeconfig=/etc/kubernetes/controller-manager.conf#--kubeconfig=/etc/kubernetes/controller-manager.config#' /etc/kubernetes/manifests/kube-controller-manager.yaml"
  sleep 5; ns ts8; kubectl -n ts8 create deploy late --image=nginx
  echo "Broken: ts8/late has 0 pods. Fix the root cause." ;;
9)
  ns ts9
  kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: db-data, namespace: ts9}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: fast-ssd
  resources: {requests: {storage: 1Gi}}
---
apiVersion: v1
kind: Pod
metadata: {name: db, namespace: ts9}
spec:
  containers:
  - name: db
    image: busybox
    command: [sh, -c, "echo ok > /data/ok; sleep 1d"]
    volumeMounts: [{name: data, mountPath: /data}]
  volumes:
  - name: data
    persistentVolumeClaim: {claimName: db-data}
EOF
  echo "Broken: ts9/db Pending. Make it Running using the cluster's existing StorageClass." ;;
10)
  ns ts10
  kubectl -n ts10 create configmap api-config --from-literal=DB_HOST=postgres.ts10.svc
  kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: api, namespace: ts10}
spec:
  replicas: 2
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers:
      - name: api
        image: busybox
        command: [sh, -c, "echo db=$DB_HOST; sleep 1d"]
        env:
        - name: DB_HOST
          valueFrom: {configMapKeyRef: {name: api-config, key: DATABASE_HOST}}
        resources:
          requests: {cpu: "50", memory: 64Mi}
EOF
  echo "Broken: ts10/api. (There may be more than one problem.)" ;;
*) echo "unknown scenario: $1"; exit 1 ;;
esac
