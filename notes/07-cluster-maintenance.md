# 07: Cluster architecture, installation and maintenance: kubeadm, upgrades, etcd, drain, Helm, Kustomize, CRDs

Domain: **Cluster Architecture, Installation & Configuration (25%)**. RBAC and certs are in `04-security.md`. Static pods and admission are in `02-...md`.
Remember: kind can't run kubeadm install/upgrade. Read this, then do those parts on **Killercoda** (kubeadm scenarios) at least twice.

Tags: 🔥 HIGH · 🟡 MEDIUM · 🧊 LOW

---

## The big picture in one story: the football club ⚽

| Component | ⚽ Football club | 🍽 Restaurant | ✈️ Airport | 🚗 Car |
|---|---|---|---|---|
| kube-apiserver | the club's front office: every request goes through it | the head waiter: all orders go through them | the control tower: every plane talks only to it | the dashboard/ECU everything reports to |
| etcd | the club's official records book (contracts, squad list) | the order book | the flight database | the car's memory chip |
| kube-scheduler | the coach deciding who plays where | the host assigning tables | gate assignment | — |
| kube-controller-manager | the assistant coaches who keep fixing things ("we need 11 on the pitch!") | the floor manager: "table 4 needs a waiter" | ground ops making sure every gate has staff | cruise control: keeps reality = target |
| kubelet | the captain on the pitch who makes things actually happen | the chef at each station | the crew on each plane | the engine |
| container runtime (containerd) | the players' legs | the stove | the jet engines | the pistons |
| kube-proxy | the passing patterns | the runners between kitchen and tables | the baggage belts | the gearbox |
| kubeadm | the federation's official "how to found a club" kit | the franchise starter kit | the airport construction company | the factory assembly line |
| Upgrade | moving up one league at a time | renovating one section at a time | upgrading one terminal at a time | servicing a car one part at a time |
| drain / cordon | resting a player: cordon = "don't pick him", drain = "sub him off now" | closing a section: no new guests (cordon), move current guests (drain) | closing a runway for repair | parking a car for service |
| etcd backup | photocopying the club records book | photo of the order book | backup of the flight database | dashcam backup |
| Helm | buying a complete kit package (kit + boots + training plan) and choosing sizes | a meal kit with options (`--set spicy=true`) | a charter package | buying a car with an options package |
| Kustomize | adjusting the home kit for away games without a new design | the same recipe, adjusted per branch | — | the same model with local plates |
| CRD | the federation adds a new kind of license (e.g. "VAR referee") | a new kind of menu item | a new kind of vehicle on the apron | an aftermarket add-on |

---

## 1. Where everything lives on a kubeadm control plane 🔥 HIGH

```
/etc/kubernetes/
├── manifests/            # STATIC PODS: etcd.yaml kube-apiserver.yaml kube-controller-manager.yaml kube-scheduler.yaml
├── pki/                  # certificates (see 04-security.md)
├── admin.conf            # admin kubeconfig (cp to ~/.kube/config)
├── super-admin.conf      # break-glass admin (bypasses RBAC via system:masters)
├── kubelet.conf          # kubelet's kubeconfig
├── controller-manager.conf, scheduler.conf
/var/lib/kubelet/config.yaml          # kubelet config (staticPodPath, clusterDNS, cgroupDriver, clientCAFile...)
/var/lib/etcd/                        # etcd data (hostPath in etcd.yaml)
/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf   # kubelet systemd drop-in (flags, env files)
/var/lib/kubelet/kubeadm-flags.env    # extra kubelet flags written by kubeadm
/etc/containerd/config.toml           # containerd config (SystemdCgroup = true)
```
On worker nodes: no `manifests/` content and no admin.conf, but kubelet + containerd are the same.

---

## 2. Installing a cluster with kubeadm 🟡 MEDIUM (CRI/CNI prep pieces are 🔥)

### Analogy
⚽ **Founding a club:** prepare the ground (node prereqs) → hire the stadium crew (containerd) → install the club office (kubeadm/kubelet/kubectl packages) → found the club (`kubeadm init`) → paint the pitch lines so players can move (CNI) → sign players (`kubeadm join`).

### Step 1: node prerequisites (every node)
```bash
swapoff -a ; sed -i '/ swap / s/^/#/' /etc/fstab        # kubelet doesn't want swap (by default)

cat <<EOF > /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
modprobe overlay ; modprobe br_netfilter

cat <<EOF > /etc/sysctl.d/k8s.conf                       # 🔥 PERSISTED in /etc/sysctl.d, not just `sysctl -w`
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system
sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables     # verify = 1
```

### Step 2: container runtime (CRI)
```bash
# containerd (from apt, or as given in the task)
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml   # match the kubelet's systemd cgroup driver
systemctl restart containerd ; systemctl enable containerd

# 🔥 exam pattern: install a given .deb (e.g. cri-dockerd) and start it
dpkg -i /root/cri-dockerd_*.deb
systemctl enable --now cri-docker.service
systemctl status cri-docker
```

### Step 3: packages (pkgs.k8s.io, one repo PER MINOR version)
```bash
# /etc/apt/sources.list.d/kubernetes.list
deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /
apt-get update && apt-get install -y kubelet kubeadm kubectl && apt-mark hold kubelet kubeadm kubectl
systemctl enable --now kubelet          # crash-loops until kubeadm init/join. That's normal
```

### Step 4: init (control plane) and CNI
```bash
kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=<cp-ip> [--kubernetes-version=v1.37.x] [--cri-socket=unix:///var/run/cri-dockerd.sock]
mkdir -p ~/.kube && cp /etc/kubernetes/admin.conf ~/.kube/config
# install the CNI (06-networking.md §2), with the SAME pod CIDR
k get no            # Ready after the CNI is up
```

### Step 5: join workers
```bash
kubeadm token create --print-join-command        # on the control plane (tokens expire after 24h)
kubeadm join <cp-ip>:6443 --token abc.123 --discovery-token-ca-cert-hash sha256:...   # on the worker
```
Reset a node completely: `kubeadm reset -f` (then clean `/etc/cni/net.d`, iptables).

---

## 3. Upgrading a cluster with kubeadm 🔥 HIGH

### Analogies
- ⚽ **Promotion one league at a time:** 1.36 → 1.37 → 1.38. You can't skip a league (minor version).
- ✈️ **Upgrade one terminal at a time:** the control plane (control tower) first, then each terminal (worker), closing each one (drain) while it's being upgraded.
- 🚗 **Service order:** upgrade the tool (kubeadm), then the engine control (control-plane components), then the driver's dashboard (kubelet/kubectl).

### Version skew rules (know these)
- Upgrade **one minor version at a time**.
- Control plane first, then workers.
- kubelet may be **older** than the API server by up to 3 minors, **never newer**.
- kubectl: ±1 minor of the API server.

### Control plane node
```bash
# 0. Which version is available? Change the repo to the NEW minor first!
vim /etc/apt/sources.list.d/kubernetes.list          # v1.36 → v1.37
apt-get update
apt-cache madison kubeadm                            # pick the exact 1.37.x-y

# 1. kubeadm
apt-mark unhold kubeadm && apt-get install -y kubeadm='1.37.x-*' && apt-mark hold kubeadm
kubeadm version
kubeadm upgrade plan                                 # shows what it will do
kubeadm upgrade apply v1.37.x                        # FIRST control plane only (others: kubeadm upgrade node)

# 2. kubelet + kubectl (drain first)
kubectl drain <cp-node> --ignore-daemonsets
apt-mark unhold kubelet kubectl && apt-get install -y kubelet='1.37.x-*' kubectl='1.37.x-*' && apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet
kubectl uncordon <cp-node>
```

### Each worker node
```bash
# from the control plane:
kubectl drain node01 --ignore-daemonsets --delete-emptydir-data
# on node01 (ssh):
vim /etc/apt/sources.list.d/kubernetes.list ; apt-get update
apt-mark unhold kubeadm && apt-get install -y kubeadm='1.37.x-*' && apt-mark hold kubeadm
kubeadm upgrade node                                 # upgrades the local kubelet config
apt-mark unhold kubelet kubectl && apt-get install -y kubelet='1.37.x-*' kubectl='1.37.x-*' && apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet
exit
# back on the control plane:
kubectl uncordon node01
kubectl get no                                       # VERSION column shows the new version
```
⚠️ Traps: forgetting to change the apt repo (`apt-cache madison` shows only old versions), running `drain` **on the worker** (it has no kubeconfig; drain from the control plane), forgetting `uncordon`, forgetting to `exit` the ssh session.

Docs page: "Upgrading kubeadm clusters" (bookmark it, the commands are copy-paste ready there).

---

## 4. Node maintenance: cordon, drain, uncordon 🔥 HIGH

### Analogies
- 🍽 **Restaurant section closing:** `cordon` = put a "reserved/closed" sign: no **new** guests seated there, current guests keep eating. `drain` = close the sign **and** politely move the current guests to other tables. `uncordon` = remove the sign.
- 🅿️ **Car park level under repair:** cordon = no new cars may enter that level. Drain = tow the parked cars to another level. DaemonSet pods = the level's own security guard: they don't move (`--ignore-daemonsets`).

```bash
k cordon node01                       # SchedulingDisabled, existing pods stay
k drain node01 --ignore-daemonsets --delete-emptydir-data
#   --ignore-daemonsets    DaemonSet pods can't be moved (they'd come back), so skip them. Almost always needed
#   --delete-emptydir-data pods with emptyDir lose that data → you must agree
#   --force                also delete BARE pods (no controller) → they're gone forever, not recreated
#   --grace-period / --timeout
k uncordon node01
k get no                              # STATUS Ready,SchedulingDisabled while cordoned
```
⚠️ Drain is blocked by a **PodDisruptionBudget** that would be violated (`Cannot evict pod as it would violate the pod's disruption budget`). Check `k get pdb -A`. ⚽ A PDB = "the club must always have at least 2 goalkeepers available".
When a node goes **down without draining**, its pods are marked for eviction after ~5 min (default `tolerationSeconds: 300` for `node.kubernetes.io/unreachable`/`not-ready`), then controllers recreate them elsewhere.

---

## 5. etcd backup and restore 🔥 HIGH

### Analogies
- 📒 **The club's records book:** etcd holds **every** object. A snapshot = photocopying the whole book. Restore = throwing away the current book and using the photocopy, which means everything written after the copy is **lost** (that's why drill 1.3 checks that `canary` disappears).
- 🚗 **Dashcam backup:** you save the recording to a USB stick (snapshot file). Later you replace the car's memory with the USB recording.

### Tools
- `etcdctl`: talks to a **running** etcd over the network (needs endpoints + certs). Used for `snapshot save`, `member list`, `endpoint health`, `get`.
- `etcdutl`: works on **files** offline. Used for `snapshot restore`, `snapshot status`. (`etcdctl snapshot restore` is deprecated but still works on many versions.)
- `ETCDCTL_API=3` is the default in modern etcdctl. Setting it does no harm.

### Get the facts from the manifest (don't memorize the paths)
```bash
grep -E 'listen-client-urls|advertise-client|cert-file|key-file|trusted-ca-file|data-dir' /etc/kubernetes/manifests/etcd.yaml
#   --listen-client-urls=https://127.0.0.1:2379,https://<ip>:2379
#   --cert-file=/etc/kubernetes/pki/etcd/server.crt
#   --key-file=/etc/kubernetes/pki/etcd/server.key
#   --trusted-ca-file=/etc/kubernetes/pki/etcd/ca.crt
#   --data-dir=/var/lib/etcd
```

### Backup
```bash
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /opt/etcd-backup.db
etcdutl snapshot status /opt/etcd-backup.db -w table          # verify: hash, revision, keys, size
```
Flag name mapping (classic confusion): manifest `--trusted-ca-file` → etcdctl `--cacert`; `--cert-file` → `--cert`; `--key-file` → `--key`.

### Restore (stacked etcd, kubeadm)
```bash
etcdutl snapshot restore /opt/etcd-backup.db --data-dir=/var/lib/etcd-from-backup
vim /etc/kubernetes/manifests/etcd.yaml
#   volumes:
#   - hostPath:
#       path: /var/lib/etcd-from-backup     ← change THIS (the etcd-data volume)
#       type: DirectoryOrCreate
#     name: etcd-data
# (you can leave --data-dir=/var/lib/etcd: inside the container the mountPath is still /var/lib/etcd)
# save → kubelet recreates etcd → the API server reconnects (1–3 min)
watch crictl ps                  # etcd and kube-apiserver come back up
k get deploy                      # objects created after the snapshot are gone
```
Optional, cleaner: move the other static manifests out first (`mv /etc/kubernetes/manifests/kube-apiserver.yaml /root/`) so nothing writes during the restore, then move them back.
If the API server stays down: `crictl ps -a | grep etcd` → `crictl logs <id>` (path wrong? permissions?).
Other variants: if a task says etcd is **external** (a separate server/systemd service), restore there and fix `--data-dir` in its systemd unit, then `systemctl daemon-reload && systemctl restart etcd`.

```bash
etcdctl ... member list -w table        # etcd cluster members
etcdctl ... endpoint health
```

---

## 6. Helm 🔥 HIGH

### Analogies
- 🍽 **Meal kit:** a chart = a box with the recipe (templates) + default options (`values.yaml`). You order it with your options (`--set size=large`). Each order = a **release** with a name. Changing the order = `upgrade` (new **revision**). "The old one was better" = `rollback`.
- 🚗 **Car with options package:** the base model (chart) + your choices (values) = your car (release). Version 2 of the model = a new chart `--version`.
- 📱 **App store:** repos = stores (`helm repo add`), `helm search` = browse, `helm install` = install the app.

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami ; helm repo update
helm repo list
helm search repo nginx [--versions]            # in added repos
helm search hub nginx                          # Artifact Hub (internet)
helm show values bitnami/nginx | less          # what can I --set?
helm show chart bitnami/nginx

helm install web bitnami/nginx -n web --create-namespace --version 15.0.0 \
     --set replicaCount=2 --set service.type=NodePort -f my-values.yaml
helm install web ./mychart                     # local chart folder
helm install web oci://registry.example.com/charts/nginx --version 1.2.3   # OCI registry
helm upgrade web bitnami/nginx -n web --set replicaCount=3 [--reuse-values]
helm upgrade --install web bitnami/nginx -n web     # install if missing, else upgrade
helm list -A                                   # releases in ALL namespaces (-a also shows failed/pending)
helm history web -n web
helm rollback web 1 -n web
helm get values web -n web [--all]             # what values were used
helm get manifest web -n web                   # the rendered YAML in the cluster
helm template web bitnami/nginx --set replicaCount=2 > out.yaml   # render WITHOUT installing (exam: "save the manifest")
helm install web bitnami/nginx --skip-crds     # don't install the chart's CRDs (exam: "CRDs disabled")
helm pull bitnami/nginx --untar --version 15.0.0   # download the chart folder
helm uninstall web -n web
```
⚠️ Traps: forgetting `-n <ns>` (release not found), installing into `default` by mistake, chart **version** (`--version`) vs app version (`helm search` shows both).

---

## 7. Kustomize 🔥 HIGH

### Analogies
- ⚽ **Home and away kits:** the base design is the same (base). The away overlay changes the colour and adds a sponsor (patches, labels) without redrawing the whole kit.
- 🍽 **One recipe, many branches:** the base recipe + "Tashkent branch: extra spicy, 3 chefs" overlay.
- No templates, no variables: **plain YAML + patches**. Built into kubectl (`-k`).

```
app/
├── base/
│   ├── kustomization.yaml
│   ├── deploy.yaml
│   └── svc.yaml
└── overlays/
    ├── dev/kustomization.yaml
    └── prod/
        ├── kustomization.yaml
        └── replicas-patch.yaml
```
```yaml
# base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [deploy.yaml, svc.yaml]
---
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [../../base]
namespace: prod
namePrefix: prod-
labels:                              # (commonLabels is deprecated)
- pairs: {env: prod}
  includeSelectors: true             # also add to selectors (only on NEW objects! selectors are immutable)
images:
- name: nginx                        # image name as written in the base
  newName: nginx
  newTag: "1.28"
replicas:
- name: web
  count: 3
configMapGenerator:                  # generates a CM with a hash suffix → pods roll when the content changes
- name: web-cfg
  literals: [MODE=prod]
patches:
- path: replicas-patch.yaml          # strategic-merge patch (looks like a partial object)
- target: {kind: Deployment, name: web}
  patch: |-                          # JSON6902 patch
    - op: add
      path: /spec/template/spec/containers/0/env
      value: [{name: LOG, value: info}]
```
```bash
k kustomize overlays/prod            # render (check before applying!)
k apply -k overlays/prod
k delete -k overlays/prod
k diff -k overlays/prod
```

---

## 8. CRDs and operators 🔥 HIGH

### Analogies
- ⚽ **New license type:** the federation (API server) learns a new kind of document, e.g. "VAR referee license" (a CRD). After that, clubs can issue those licenses (custom resources). But someone has to actually **act** on them (the operator/controller), otherwise it's just paperwork.
- 🍽 **New menu category:** adding "sushi" to the menu (CRD) is useless without a sushi chef (operator).

```bash
k get crd                                        # all CRDs
k get crd | grep cert-manager > /root/crds.txt   # exam: "list cert-manager CRDs to a file"
k get crd certificates.cert-manager.io -o yaml | less
k explain certificate.spec --api-version=cert-manager.io/v1          # exam: "write the docs of field X to a file"
k explain certificate.spec.subject > /root/subject.txt
k api-resources --api-group=cert-manager.io
k get certificates -A                            # the custom resources themselves
```
Minimal CRD (🧊 writing one from scratch is rare; reading them is common):
```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.example.com          # <plural>.<group>
spec:
  group: example.com
  scope: Namespaced
  names: {plural: backups, singular: backup, kind: Backup, shortNames: [bk]}
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              schedule: {type: string}
```
Operators are usually installed with Helm or a manifest (`k apply -f operator.yaml` / `k create -f`), then you create the custom resource they watch.

---

## 9. High-availability control plane 🧊 LOW

- **Stacked etcd:** etcd runs on each control-plane node (kubeadm default). Simple, but losing a node loses an etcd member too.
- **External etcd:** etcd on separate machines. More machines, more resilient.
- etcd needs a **majority (quorum)**: 3 members tolerate 1 failure, 5 tolerate 2. Use odd numbers.
- The API servers are active-active behind a load balancer (`--control-plane-endpoint`). The scheduler and controller-manager are **active-passive** via leader election (only one acts).
⚽ Three referees (etcd members) vote on every decision. If one is injured, 2 out of 3 can still decide. If two are injured, the match stops.

---

## 10. Self-check

1. Order of upgrade steps on the first control plane?
2. `apt-cache madison kubeadm` shows only 1.36.x. Why?
3. Worker upgrade: which `kubeadm upgrade` subcommand?
4. Where do you run `kubectl drain`, and which flag is almost always needed?
5. Drain says "cannot delete Pods not managed by ReplicationController, ReplicaSet, Job, DaemonSet or StatefulSet". What flag, and what's the consequence?
6. Which etcdctl flags map to `--trusted-ca-file`, `--cert-file`, `--key-file`?
7. After `etcdutl snapshot restore --data-dir /var/lib/etcd-new`, what must you change and where?
8. How do you render a Helm chart to a file without installing it?
9. How do you install a chart without its CRDs?
10. What does `includeSelectors: true` do in Kustomize labels, and why be careful?
11. Which sysctls must be 1 for Kubernetes networking, and where do you persist them?
12. Why `SystemdCgroup = true` in containerd?

<details><summary>Answers</summary>

1. Change the apt repo → upgrade kubeadm → `kubeadm upgrade plan` → `kubeadm upgrade apply v1.37.x` → drain → upgrade kubelet + kubectl → `daemon-reload` + restart kubelet → uncordon.
2. The apt repo still points to the v1.36 pkgs.k8s.io channel. Edit `/etc/apt/sources.list.d/kubernetes.list`, then `apt-get update`.
3. `kubeadm upgrade node`.
4. From a machine with a working kubeconfig (the control plane / your exam host). `--ignore-daemonsets`.
5. `--force`. Those bare pods are deleted and never come back.
6. `--cacert`, `--cert`, `--key`.
7. The `hostPath.path` of the etcd-data volume in `/etc/kubernetes/manifests/etcd.yaml` (or the `--data-dir` + mount consistently).
8. `helm template <release> <chart> [--set ...] > file.yaml`.
9. `--skip-crds`.
10. It adds the labels to selectors too. Selectors of existing Deployments are immutable, so applying to existing objects can fail.
11. `net.ipv4.ip_forward`, `net.bridge.bridge-nf-call-iptables` (+ ip6tables), in `/etc/sysctl.d/*.conf`, then `sysctl --system`.
12. The kubelet uses the systemd cgroup driver by default. containerd must use the same, otherwise pods/kubelet misbehave.
</details>

---

## 11. Mini-drills (≈90 min; kind + Killercoda)

```bash
# A. etcd (kind, 15 min ×3): drill 1.3 blind. Then do it again moving the apiserver manifest out during restore.
# B. Drain (kind, 10 min): create a deploy (4 replicas), a bare pod, a DaemonSet-pod. Drain cka-worker.
#    Read each error, add the right flag, uncordon. Add a PDB minAvailable: 4 and see drain get blocked.
# C. Helm (kind, 15 min): drill 1.4 + helm template to /root/out.yaml + helm show values | grep replica.
# D. Kustomize (kind, 15 min): drill 1.5 + an images: override + a configMapGenerator; edit the literal, re-apply, watch pods roll.
# E. CRDs (kind, 5 min): drill 1.6, write the output of k explain to a file and cat it.
# F. kubeadm upgrade + join (Killercoda, 30 min ×2): https://killercoda.com/killer-shell-cka
# G. CRI prep (Killercoda/any VM, 10 min): write /etc/modules-load.d/k8s.conf + /etc/sysctl.d/k8s.conf from memory, sysctl --system, verify.
```
