---
tags:
  - cka/practice
---

[[00 Home|🏠 Home]]

# CKA drills (k8s v1.37, run on the kind "cka" cluster)

Speed matters: aim for under 6 minutes per task. Use `$do` for YAML scaffolds, and use https://kubernetes.io/docs (the only site allowed in the exam) instead of Google.
Put your answers in `drills/work/` (gitignored).

---

## 1. Cluster Architecture, Installation & Configuration (25%)

**1.1 RBAC.** In ns `dev`, create ServiceAccount `deployer` that can `get,list,create,update` Deployments and nothing else. Prove it with `auth can-i`.
> [!success]- solution
> ```bash
> k create ns dev
> k -n dev create sa deployer
> k -n dev create role deployer --verb=get,list,create,update --resource=deployments
> k -n dev create rolebinding deployer --role=deployer --serviceaccount=dev:deployer
> k -n dev auth can-i create deployments --as=system:serviceaccount:dev:deployer   # yes
> k -n dev auth can-i delete deployments --as=system:serviceaccount:dev:deployer   # no
> ```

**1.2 ClusterRole.** User `jane` must be able to list Nodes and PersistentVolumes cluster-wide.
> [!success]- solution
> ```bash
> k create clusterrole node-pv-reader --verb=get,list --resource=nodes,persistentvolumes
> k create clusterrolebinding jane-node-pv --clusterrole=node-pv-reader --user=jane
> k auth can-i list nodes --as=jane
> ```

**1.3 etcd backup + restore.** On the control plane, snapshot etcd to `/opt/etcd-backup.db`. Create a deployment `canary`, then restore the snapshot and confirm `canary` is gone.
> [!success]- solution
> ```bash
> ./cluster/ssh.sh cp
> # get cert paths from the static pod manifest; don't memorize them
> grep -E 'cert|key|trusted|listen-client' /etc/kubernetes/manifests/etcd.yaml
> etcdctl --endpoints=https://127.0.0.1:2379 \
>   --cacert=/etc/kubernetes/pki/etcd/ca.crt \
>   --cert=/etc/kubernetes/pki/etcd/server.crt \
>   --key=/etc/kubernetes/pki/etcd/server.key \
>   snapshot save /opt/etcd-backup.db
> etcdutl snapshot status /opt/etcd-backup.db -w table
> # (exit, kubectl create deploy canary --image=nginx, ssh back in)
> etcdutl snapshot restore /opt/etcd-backup.db --data-dir /var/lib/etcd-restore
> vim /etc/kubernetes/manifests/etcd.yaml   # hostPath of etcd-data volume -> /var/lib/etcd-restore
> # wait ~1-2 min for etcd + apiserver to restart
> ```

**1.4 Helm.** Add the bitnami repo, install chart `bitnami/nginx` as release `web` in ns `helm-lab` with `replicaCount=2`. Then upgrade it to `replicaCount=3`, roll back to revision 1, and list the history.
> [!success]- solution
> ```bash
> helm repo add bitnami https://charts.bitnami.com/bitnami && helm repo update
> helm search repo bitnami/nginx --versions | head
> helm install web bitnami/nginx -n helm-lab --create-namespace --set replicaCount=2
> helm upgrade web bitnami/nginx -n helm-lab --set replicaCount=3
> helm rollback web 1 -n helm-lab
> helm history web -n helm-lab
> helm get values web -n helm-lab
> ```

**1.5 Kustomize.** Make a `base/` with an nginx Deployment and an `overlays/prod/` that sets namespace `prod`, prefix `prod-`, `replicas: 3`, and label `env=prod`. Apply it with `kubectl apply -k`.
> [!success]- solution
> ```yaml
> # base/kustomization.yaml
> resources: [deploy.yaml]
> # overlays/prod/kustomization.yaml
> resources: [../../base]
> namespace: prod
> namePrefix: prod-
> labels:
> - pairs: {env: prod}
>   includeSelectors: true
> replicas:
> - name: nginx
>   count: 3
> ```
> `k create ns prod; k kustomize overlays/prod; k apply -k overlays/prod`

**1.6 CRD.** List all CRDs installed by Calico, then show the spec fields of `ippools.crd.projectcalico.org`.
> [!success]- solution
> `k get crd | grep calico` · `k explain ippools.spec --api-version=crd.projectcalico.org/v1` (or `k get crd ippools.crd.projectcalico.org -o yaml`)

**1.7 kubeadm (knowledge).** Write down the upgrade sequence for a control plane node from 1.36 to 1.37. You can't run it on kind, but it IS on the exam. Read: https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/
> [!success]- solution
> ```
> apt-mark unhold kubeadm && apt-get update && apt-get install -y kubeadm='1.37.x-*' && apt-mark hold kubeadm
> kubeadm upgrade plan
> kubeadm upgrade apply v1.37.x          # first CP only; other CPs: kubeadm upgrade node
> kubectl drain <cp> --ignore-daemonsets
> apt-get install kubelet='1.37.x-*' kubectl='1.37.x-*'
> systemctl daemon-reload && systemctl restart kubelet
> kubectl uncordon <cp>
> # workers: kubeadm upgrade node, then drain/kubelet/uncordon
> ```
> Also know `kubeadm token create --print-join-command` and `kubeadm certs check-expiration`.

---

## 2. Workloads & Scheduling (15%)

**2.1** Deployment `web` (nginx:1.27, 3 replicas). Roll to `nginx:1.28`, check history, then undo.
> [!success]- solution
> ```bash
> k create deploy web --image=nginx:1.27 --replicas=3
> k set image deploy/web nginx=nginx:1.28
> k rollout status deploy/web; k rollout history deploy/web; k rollout undo deploy/web
> ```

**2.2** ConfigMap `app-cfg` (`MODE=prod`) and Secret `app-sec` (`PASSWORD=s3cr3t`). Pod `cfg` uses MODE as an env var and mounts the secret at `/etc/sec`.
> [!success]- solution
> ```bash
> k create cm app-cfg --from-literal=MODE=prod
> k create secret generic app-sec --from-literal=PASSWORD=s3cr3t
> k run cfg --image=busybox $do -- sleep 1d > cfg.yaml
> ```
> Add under the container: `envFrom: [{configMapRef: {name: app-cfg}}]` and `volumeMounts: [{name: s, mountPath: /etc/sec}]`. Add under spec: `volumes: [{name: s, secret: {secretName: app-sec}}]`.

**2.3 HPA.** Deployment `php` (`registry.k8s.io/hpa-example`, cpu request 200m). HPA: min 1, max 5, 50% CPU.
> [!success]- solution
> ```bash
> k create deploy php --image=registry.k8s.io/hpa-example --port=80
> k set resources deploy php --requests=cpu=200m
> k autoscale deploy php --min=1 --max=5 --cpu-percent=50
> k get hpa -w
> ```

**2.4 Scheduling.** Label `cka-worker2` with `disk=ssd`. Pod `fast` must run there (nodeAffinity, required). Then taint `cka-worker` with `dedicated=infra:NoSchedule` and create pod `infra` that tolerates it and runs on it.
> [!success]- solution
> ```bash
> k label node cka-worker2 disk=ssd
> k taint node cka-worker dedicated=infra:NoSchedule
> ```
> ```yaml
> affinity:
>   nodeAffinity:
>     requiredDuringSchedulingIgnoredDuringExecution:
>       nodeSelectorTerms:
>       - matchExpressions: [{key: disk, operator: In, values: [ssd]}]
> ---
> tolerations: [{key: dedicated, operator: Equal, value: infra, effect: NoSchedule}]
> nodeSelector: {kubernetes.io/hostname: cka-worker}
> ```
> Clean up: `k taint node cka-worker dedicated-`

**2.5 Native sidecar.** Pod `logger`: main container busybox writes the date to `/var/log/app.log` every 2s. Add a native sidecar (initContainer with `restartPolicy: Always`) that `tail -F`s it from a shared emptyDir.
> [!success]- solution
> ```yaml
> spec:
>   initContainers:
>   - name: tail
>     image: busybox
>     restartPolicy: Always
>     command: [sh, -c, "tail -F /var/log/app.log"]
>     volumeMounts: [{name: logs, mountPath: /var/log}]
>   containers:
>   - name: app
>     image: busybox
>     command: [sh, -c, "while true; do date >> /var/log/app.log; sleep 2; done"]
>     volumeMounts: [{name: logs, mountPath: /var/log}]
>   volumes: [{name: logs, emptyDir: {}}]
> ```
> `k logs logger -c tail`

**2.6 PriorityClass.** Create PriorityClass `high` (value 1000000). Deployment `critical` uses it.
> [!success]- solution
> `k create priorityclass high --value=1000000 --description="critical"` then `priorityClassName: high` in the pod spec.

**2.7 Resources.** In ns `quota`: a LimitRange (default container cpu 200m / mem 128Mi) and a ResourceQuota (max 4 pods, 1 CPU of requests).
> [!success]- solution
> `k create quota q -n quota --hard=pods=4,requests.cpu=1`. LimitRange has no imperative command; copy the YAML from the docs ("Configure Default Memory Requests and Limits").

---

## 3. Storage (10%)

**3.1** Create a hostPath PV `pv-log` (100Mi, RWO, `/pv/log`, storageClassName `manual`), a PVC `pvc-log` bound to it, and a pod mounting it at `/log`.
**3.2** StorageClass `fast` (provisioner `rancher.io/local-path`, `reclaimPolicy: Retain`, `volumeBindingMode: WaitForFirstConsumer`, `allowVolumeExpansion: true`). Make it the default and remove the default flag from `standard`.
> [!success]- solution
> ```bash
> k patch sc standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
> ```
> Then add the annotation `storageclass.kubernetes.io/is-default-class: "true"` to `fast`. Read about access modes (RWO/ROX/RWX/RWOP) and reclaim policies in the docs.

---

## 4. Services & Networking (20%)

**4.1** Expose deployment `web` as a NodePort on 30080, then open http://localhost:30080 on your host (kind maps it).
> [!success]- solution
> `k expose deploy web --type=NodePort --port=80 $do > svc.yaml` → set `nodePort: 30080` → apply. kind forwards host:30080 to the control-plane node, and kube-proxy routes it to the pods on any node.

**4.2 DNS.** From a busybox pod, resolve the service `web` (short name), its FQDN, and a pod by its dashed-IP DNS name.
> [!success]- solution
> `web`, `web.default.svc.cluster.local`, `192-168-1-5.default.pod.cluster.local` (use a real pod IP from `k get po -o wide`) → `k run t --rm -it --image=busybox -- nslookup ...`

**4.3 NetworkPolicy (ns + pod selector).** In ns `np`, pods labelled `role=db` may only receive traffic from `role=api` in namespace `app` (namespaceSelector AND podSelector in ONE `from` item) on 5432.
> [!success]- solution
> ```yaml
> ingress:
> - from:
>   - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: app}}
>     podSelector: {matchLabels: {role: api}}     # same list item = AND
>   ports: [{port: 5432}]
> ```

**4.4 Gateway API** (needs `./cluster/up.sh --gateway`). Create a Gateway `web-gw` (class `nginx`, HTTP listener port 80) and an HTTPRoute sending `/` to service `web:80`. Bonus: route `/v2` to `web-v2` with a 80/20 weight split.
> [!success]- solution
> ```yaml
> apiVersion: gateway.networking.k8s.io/v1
> kind: Gateway
> metadata: {name: web-gw}
> spec:
>   gatewayClassName: nginx
>   listeners: [{name: http, protocol: HTTP, port: 80}]
> ---
> apiVersion: gateway.networking.k8s.io/v1
> kind: HTTPRoute
> metadata: {name: web}
> spec:
>   parentRefs: [{name: web-gw}]
>   rules:
>   - matches: [{path: {type: PathPrefix, value: /}}]
>     backendRefs: [{name: web, port: 80}]
> ```
> `k get gateway,httproute` · find the NodePort of the gateway svc and curl it via `docker exec cka-worker curl localhost:<np>`.

**4.5** Find the cluster's Pod CIDR, Service CIDR, and the CNI in use, without googling.
> [!success]- solution
> `k cluster-info dump | grep -m1 -E 'cluster-cidr|service-cluster-ip-range'` · `ls /etc/cni/net.d` on a node · `k -n kube-system get pods`

---

## 5. Troubleshooting (30%)
→ `./troubleshoot/break.sh list`. Do all 10, several times, until each takes under 5 minutes.
Also practise: `k top nodes/pods --sort-by=cpu`, `k get events -A --sort-by=.lastTimestamp`, `k logs -p`, `crictl ps -a`, `journalctl -u kubelet`.
