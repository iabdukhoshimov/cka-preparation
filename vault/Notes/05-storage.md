---
tags:
  - cka/storage
---

← [[04-security]] · [[00 Home|🏠 Home]] · [[06-networking]] →

# 05: Storage: volumes, PV, PVC, StorageClass, access modes, expansion

Domain: **Storage (10%)**. It's small but easy points, and it shows up inside troubleshooting tasks ("pod Pending because PVC Pending").

Tags: 🔥 HIGH · 🟡 MEDIUM · 🧊 LOW

---

## The big picture in one story: parking 🅿️

| Storage object | 🅿️ Parking | 🏨 Hotel | 🎬 Cinema |
|---|---|---|---|
| Container filesystem | sitting in the car: gone when the car is scrapped (container restarts → data lost) | your hand luggage | popcorn on your lap |
| `emptyDir` | a shared boot space for everyone in the same car, gone when the car leaves | the room minibar: lasts your stay | the armrest cup holder between friends, cleared after the film |
| `hostPath` | a spot in **one specific** car park (one node). Move to another car park, your stuff isn't there | storage room in **one** branch of the hotel chain | a locker in **one** cinema |
| **PersistentVolume (PV)** | an actual, numbered parking space that exists (admin built it) | a real hotel room | a real seat |
| **PersistentVolumeClaim (PVC)** | your request: "I need a spot, at least 10 m², for one car" | your booking: "a double room, 2 nights" | your ticket request: "2 seats, middle row" |
| Binding | the attendant matches your request to a free space and writes your name on it | the reception assigns room 204 to your booking | the cashier assigns seats F7–F8 |
| **StorageClass** | the valet company that **builds a new space on demand** (dynamic provisioning) | a hotel that adds a room when you book | a pop-up cinema that adds seats when tickets sell |
| `reclaimPolicy: Delete` | when you leave, the space is demolished | room is cleared and removed | seat is cleaned and freed |
| `reclaimPolicy: Retain` | when you leave, your stuff stays and the space is locked until the manager clears it | your luggage stays in the room until staff decide | your coat stays on the seat until staff collect it |
| `WaitForFirstConsumer` | the valet only builds the space once they know **which car park your car is going to** | the room is assigned when you arrive, in the branch you arrived at | the seat is assigned when you walk in |

```
Pod ──uses──▶ PVC ──bound 1:1──▶ PV ──points to──▶ real storage (disk, NFS, cloud volume, hostPath)
                      ▲
          StorageClass creates the PV automatically (dynamic provisioning)
```

Who does what:
- **Admin:** creates PVs (static) or StorageClasses (dynamic).
- **Developer:** creates PVCs and uses them in pods. **Pods never refer to a PV directly.**

---

## 1. Volumes inside a pod 🔥 HIGH

### Why
A container's own filesystem is **ephemeral**: restart the container and changes are gone. Volumes give data that survives container restarts (emptyDir), node-local files (hostPath), config (configMap/secret), or real persistent disks (PVC).

> [!example]+ Analogies for emptyDir vs hostPath vs PVC
> - 🚗 **emptyDir:** the shared boot of one car. All passengers (containers in the pod) put things in it. When the car is scrapped (pod deleted), the boot is gone. A passenger getting out and back in (container restart) doesn't empty it.
> - 🅿️ **hostPath:** a locker inside **one** car park. If tomorrow you park in a different car park (pod rescheduled to another node), your locker isn't there. Also dangerous: the locker is in the building's control room (node filesystem). That's why security folks hate it.
> - 🏦 **PVC:** a bank safe-deposit box. It follows *you*, not the car park (for network storage). It survives the pod.

```yaml
apiVersion: v1
kind: Pod
metadata: {name: vols}
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    volumeMounts:
    - {name: scratch, mountPath: /scratch}
    - {name: cache,   mountPath: /cache}
    - {name: node-logs, mountPath: /host-logs, readOnly: true}
    - {name: data,    mountPath: /data}
    - {name: info,    mountPath: /etc/podinfo}
  volumes:
  - name: scratch
    emptyDir: {}                          # on node disk, lives as long as the POD
  - name: cache
    emptyDir: {medium: Memory, sizeLimit: 64Mi}   # tmpfs (RAM), counts against memory limit
  - name: node-logs
    hostPath:
      path: /var/log
      type: Directory                     # DirectoryOrCreate | File | FileOrCreate | Socket ...
  - name: data
    persistentVolumeClaim:
      claimName: data-pvc                 # PVC in the SAME namespace
  - name: info
    downwardAPI:                          # pod metadata as files
      items:
      - path: labels
        fieldRef: {fieldPath: metadata.labels}
```

| Volume | Lives as long as | Shared between containers of the pod? | Same data on another node? |
|---|---|---|---|
| container FS | the container | no | no |
| emptyDir | the pod | ✅ yes | no |
| hostPath | the node | ✅ | ❌ no (different node = different files) |
| PVC (network/CSI) | until PVC/PV deleted | ✅ | ✅ (that's the point) |
| PVC (local-path, kind) | until PVC/PV deleted | ✅ | ❌ (pod is pinned to that node) |

### Classic exam shape: two containers sharing one emptyDir (log sidecar)
```yaml
spec:
  containers:
  - name: writer
    image: busybox:1.36
    command: ["sh", "-c", "while true; do date >> /data/log.txt; sleep 2; done"]
    volumeMounts:
    - {name: shared, mountPath: /data}
  - name: reader
    image: busybox:1.36
    command: ["sh", "-c", "tail -F /input/log.txt"]
    volumeMounts:
    - {name: shared, mountPath: /input, readOnly: true}   # same volume, different path is fine
  volumes:
  - name: shared
    emptyDir: {sizeLimit: 100Mi}
```
Check it with `k logs <pod> -c reader`. The **volume name** must match. The mountPaths don't have to.

---

## 2. PersistentVolume (PV) 🔥 HIGH

**What:** a piece of storage in the cluster, made by an admin (static) or by a StorageClass (dynamic). **Cluster-scoped** (no namespace).

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-log
spec:
  capacity:
    storage: 100Mi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain   # static PV default = Retain
  storageClassName: manual                # any name; the PVC must ask for the SAME name
  volumeMode: Filesystem                  # or Block
  hostPath:
    path: /pv/log
  # nodeAffinity: ...                     # required for type "local:" volumes
```
No imperative command. Copy from docs: **"Configure a Pod to Use a PersistentVolume for Storage"** (has PV + PVC + Pod in one page; bookmark it).

### Access modes (🎬 cinema analogy)
| Mode | Short | 🎬 Cinema | Meaning |
|---|---|---|---|
| ReadWriteOnce | RWO | **one row** reserved for one group of friends: anyone in that group can sit and move around | read-write by pods on **one node** (several pods on the same node can share it!) |
| ReadOnlyMany | ROX | the screen: everyone in many halls can **watch**, nobody can draw on it | read-only by many nodes |
| ReadWriteMany | RWX | a shared whiteboard in the lobby: everyone from every hall can write | read-write by many nodes (NFS, CephFS, cloud file storage) |
| ReadWriteOncePod | RWOP | **one single seat** with your name on it: only one person | read-write by **one pod** only (GA 1.29) |

> [!warning]
> Access modes are about what the storage **can** do. hostPath and local-path only support RWO (and RWOP). A PVC asking `RWX` from local-path stays **Pending**.

### Reclaim policies
| Policy | When the PVC is deleted | 🅿️ |
|---|---|---|
| Retain | PV → `Released`, data kept, **not reusable** until an admin cleans it | your car is locked in the space until the manager clears it |
| Delete | PV and the underlying disk are deleted | the space is demolished |
| Recycle | ❌ deprecated (`rm -rf` then Available) | — |

### PV phases
`Available` (free) → `Bound` (to a PVC) → `Released` (PVC deleted, Retain) → (`Failed` = reclaim failed)

**Make a Released PV Available again** (exam trick):
```bash
k patch pv pv-log --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'
# or: k edit pv pv-log → delete the whole claimRef: block
```

---

## 3. PersistentVolumeClaim (PVC) 🔥 HIGH

**What:** a request for storage, **namespaced**, used by pods.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-log
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 50Mi          # PV must be >= this. It can bind to a BIGGER PV (gets the whole 100Mi)
  storageClassName: manual   # must match the PV's class
  # volumeName: pv-log       # pin to one specific PV (exam: "bind to PV X")
  # selector: {matchLabels: {tier: logs}}   # bind only to PVs with these labels
```

### Binding rules (all must be true)
1. `storageClassName` equal (see the table below).
2. PV `capacity` ≥ PVC request.
3. PV access modes include the PVC's requested modes.
4. `volumeMode` equal.
5. selector / volumeName match (if set).
6. PV is `Available`.

**One PV ↔ one PVC.** A 10Gi PV bound to a 1Gi PVC is fully used. The leftover 9Gi can't be shared.

### PVC phases
| Phase | Meaning / what to do |
|---|---|
| Pending | no matching PV → `k describe pvc` events. **With WaitForFirstConsumer, Pending is NORMAL until a pod uses it** |
| Bound | ✅ (check the VOLUME column: is it the PV you meant?) |
| Lost | the PV it was bound to disappeared |

### The storageClassName trap (🔥 explains most "Pending PVC" tasks)
| PVC `storageClassName` | What happens |
|---|---|
| `"manual"` | binds only to PVs with class `manual`, or a SC named `manual` provisions one |
| `""` (empty string) | **no dynamic provisioning**; binds only to PVs with **no class** |
| not set at all | the **default StorageClass** is filled in (DefaultStorageClass admission) → dynamic provisioning |
| `"fast-ssd"` that doesn't exist | stays Pending: `storageclass.storage.k8s.io "fast-ssd" not found` (`break.sh 9`) |

> [!warning]
> So: you made a static PV with **no** `storageClassName` and a PVC with no class either → the PVC gets `standard` (the default) and **ignores your PV**. Fix: set the same `storageClassName` on both (e.g. `manual`), or set `storageClassName: ""` on the PVC.

### Using it in a Deployment (exam: "mount the PVC at /usr/share/nginx/html")
```yaml
spec:
  template:
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        persistentVolumeClaim:
          claimName: pvc-log
```
> [!warning]
> RWO + a Deployment with replicas on **different nodes** → the 2nd pod gets stuck in `ContainerCreating` (Multi-Attach error) on real block storage. On kind/local-path, pods are pinned to the PV's node.

### 🔥 Exam pattern: "restore the MariaDB deployment" (commonly reported)
> "A MariaDB deployment was deleted by mistake. A PV with the data still exists (Retain). Create a PVC named `mariadb` in ns `mariadb` (250Mi, RWO) that binds to that PV, then edit `~/mariadb-deploy.yaml` to use the PVC and apply it."

```bash
k get pv                                    # find the PV: Available? Released? note its class, size, accessModes
k get pv <pv> -o yaml | grep -E "storageClassName|accessModes|storage|claimRef" -A1
# if Released → k patch pv <pv> --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'
cat <<EOF | k apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: mariadb, namespace: mariadb}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 250Mi}}
  storageClassName: <SAME as the PV, or "" if the PV has none>
EOF
k -n mariadb get pvc                        # must be Bound to THAT PV (VOLUME column)
vi ~/mariadb-deploy.yaml                    # volumes: - name: ... persistentVolumeClaim: {claimName: mariadb}
k apply -f ~/mariadb-deploy.yaml
k -n mariadb get po                         # Running and stable
```
Three things silently break it: a class mismatch (the PVC gets the default SC and a **new, empty** PV), the old `claimRef`, and requesting more than the PV's size.

`spec` of a PVC is mostly **immutable** (only `resources.requests.storage` can grow). To change class/accessModes: export, delete, recreate. Delete the pod first, otherwise the PVC stays `Terminating` (protected while in use: `kubernetes.io/pvc-protection` finalizer).

---

## 4. StorageClass and dynamic provisioning 🔥 HIGH

> [!example]+ Analogies
> - 🅿️ **Valet company:** you don't need an admin to pre-build spaces. You hand your ticket (PVC) to the valet company (StorageClass), they build a space (PV) to your size. Different companies = different quality: `fast` (SSD), `slow` (HDD), `retain-me` (Retain).
> - 🍽 **Made to order** vs **buffet**: static PVs = the buffet (take what's already there). StorageClass = à la carte (cooked when you order).
> - 🎬 **`WaitForFirstConsumer`:** the seat is only assigned once you're **at the cinema door** (the pod is scheduled), so you don't get a seat in a cinema in another city (a disk in another zone/node than your pod).

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"   # the default for PVCs without a class
provisioner: rancher.io/local-path      # kind's provisioner. Cloud: ebs.csi.aws.com, pd.csi.storage.gke.io...
reclaimPolicy: Retain                   # default for SCs = Delete
volumeBindingMode: WaitForFirstConsumer # or Immediate (default)
allowVolumeExpansion: true
parameters: {}                          # provisioner-specific (type: gp3, etc.)
```

| volumeBindingMode | When the PV is made/bound | PVC status before a pod uses it |
|---|---|---|
| Immediate | as soon as the PVC is created | Bound |
| WaitForFirstConsumer | when a pod using the PVC is **scheduled** | **Pending** (normal! event: `waiting for first consumer to be created before binding`) |

### Exam pattern: change the default StorageClass
```bash
k get sc                                     # "(default)" next to the name
k patch sc standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
k patch sc fast     -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
k get sc                                     # exactly ONE default
```
Most SC fields are **immutable** (provisioner, parameters, reclaimPolicy, bindingMode): to change, `k get sc x -o yaml > sc.yaml`, edit, `k replace --force -f sc.yaml`.

`no-provisioner` class for pre-made local PVs: `provisioner: kubernetes.io/no-provisioner` + `WaitForFirstConsumer` (no dynamic provisioning, only matching to existing PVs).

---

## 5. Expanding a PVC 🟡 MEDIUM

### Analogy
🅿️ You need a bigger space for a van. You can ask the valet to **extend** your space (if the company allows extensions: `allowVolumeExpansion: true`). You can never **shrink** it.

```bash
k patch pvc data -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'   # or k edit pvc data
k get pvc data -w                    # CAPACITY grows; may show condition FileSystemResizePending until a pod mounts it
k describe pvc data                  # events: "waiting for user to (re-)start a pod" for some drivers
```
Requirements: SC has `allowVolumeExpansion: true`, and the **provisioner/driver supports it**. ⚠️ kind's `local-path` and plain hostPath do **not** really resize, so practise the *steps*, not the result. Shrinking → `Forbidden: field can not be less than previous value`.

---

## 6. StatefulSets and volumeClaimTemplates 🟡 MEDIUM

### Analogy
🎬 **Season ticket holders:** each fan (pod `db-0`, `db-1`) has **their own named seat** (PVC `data-db-0`, `data-db-1`). If the fan misses a game and comes back (pod recreated), they get **the same seat** back. If the club shrinks the stadium (scale down), the seats are **kept**, not destroyed, in case the fan comes back.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: db}
spec:
  serviceName: db                      # headless service (clusterIP: None) must exist
  replicas: 2
  selector: {matchLabels: {app: db}}
  template:
    metadata: {labels: {app: db}}
    spec:
      containers:
      - name: db
        image: busybox:1.36
        command: ["sh", "-c", "hostname > /data/me; sleep 3600"]
        volumeMounts: [{name: data, mountPath: /data}]
  volumeClaimTemplates:                # one PVC PER POD: <template-name>-<pod-name> → data-db-0, data-db-1
  - metadata: {name: data}
    spec:
      accessModes: [ReadWriteOnce]
      resources: {requests: {storage: 100Mi}}
      # storageClassName omitted → default SC
  persistentVolumeClaimRetentionPolicy:   # default both Retain
    whenDeleted: Retain
    whenScaled: Retain
```
Deleting the StatefulSet does **not** delete the PVCs (by default). Clean them up yourself.

---

## 7. CSI and storage plugins 🧊 LOW

### Analogy
🚗 **CSI = the standard fuel nozzle.** Any fuel company (AWS EBS, Ceph, NetApp...) builds a nozzle that fits every car (Kubernetes). Before CSI, every company's code had to be built *into* the car ("in-tree" plugins), now removed/migrated.

Know: CSI drivers run as pods (controller + node DaemonSet), `k get csidrivers`, `k get csinodes`, `k get volumeattachments`, provisioner names look like `ebs.csi.aws.com`. Volume snapshots (`VolumeSnapshot`, `VolumeSnapshotClass`) are CSI CRDs.

---

## 8. Storage troubleshooting table 🔥 HIGH

| Symptom | `k describe` says | Cause → fix |
|---|---|---|
| PVC Pending | `storageclass "x" not found` | wrong class name → recreate PVC with an existing class |
| PVC Pending | `no persistent volumes available for this claim and no storage class is set` | static PV mismatch (size, accessModes, class) → compare `k get pv` vs PVC |
| PVC Pending | `waiting for first consumer to be created before binding` | **normal** for WaitForFirstConsumer → create the pod |
| PVC Pending, PV Available, everything "matches" | — | PVC got the default class because its class was unset; PV has none → set `storageClassName` on both |
| PV `Released`, new PVC won't bind | — | old `claimRef` still there → remove it |
| Pod Pending | `persistentvolumeclaim "x" not found` | PVC missing or in another namespace |
| Pod Pending | `node(s) had volume node affinity conflict` | local PV is on another node than where the pod can go |
| Pod ContainerCreating | `Multi-Attach error` | RWO disk already attached to another node |
| PVC stuck Terminating | — | still used by a pod (pvc-protection) → delete the pod first |
| Data gone after pod restart | — | used emptyDir/container FS instead of a PVC |

```bash
k get pv,pvc -A
k get pvc x -o yaml | grep -A3 -E 'storageClassName|accessModes'
k describe pvc x | tail -10
k get events --sort-by=.lastTimestamp | grep -i -E 'volume|claim'
```

---

## 9. Self-check

1. A PVC requests 500Mi RWO class `manual`. PVs: A (1Gi, RWO, manual), B (500Mi, RWX, manual), C (500Mi, RWO, no class). Which binds?
2. The PVC above is bound to a 1Gi PV. How much storage does it actually get?
3. What does `storageClassName: ""` mean on a PVC, compared to leaving it out?
4. kind PVC with class `standard` stays Pending right after creation. Problem?
5. Pod deleted → PVC deleted → PV shows `Released`. How do you reuse the PV?
6. Two default StorageClasses exist. What happens to a new PVC without a class?
7. Can you shrink a PVC from 2Gi to 1Gi?
8. What PVC names does StatefulSet `web` with volumeClaimTemplate `www` and 3 replicas create?
9. Difference between RWO and RWOP?
10. An emptyDir pod's container crashes and restarts. Is the data still there? And if the pod is deleted?
11. Is a PV namespaced? Is a PVC?
12. Which annotation makes a StorageClass the default?

> [!success]- Answers
> 1. A. B has the wrong access mode, C has the wrong class (no class ≠ `manual`).
> 2. The whole 1Gi (one PV ↔ one PVC).
> 3. `""` = explicitly "no class": no dynamic provisioning, bind only to class-less PVs. Leaving it out = the default SC is used.
> 4. Probably nothing: `standard` is WaitForFirstConsumer, it binds when a pod uses it.
> 5. Remove `spec.claimRef` from the PV (it becomes Available). Clean the data first if needed.
> 6. Kubernetes picks the most recently created default (older versions rejected it). Either way, fix it so only one is default.
> 7. No. Expansion only.
> 8. `www-web-0`, `www-web-1`, `www-web-2`.
> 9. RWO = one **node** (several pods on that node may use it). RWOP = exactly one **pod**.
> 10. Container restart: yes, data stays (emptyDir lives with the pod). Pod deleted: gone.
> 11. PV: no (cluster-scoped). PVC: yes.
> 12. `storageclass.kubernetes.io/is-default-class: "true"`

---

## 10. Mini-drills in your kind lab (≈45 min)

```bash
# A. Static PV/PVC/pod (10 min): drills 3.1. Write a file from the pod, delete the pod, recreate it,
#    check the file is still there. Then ./cluster/ssh.sh <node> and ls /pv/log on the node.

# B. The class trap (5 min): create a PV with NO storageClassName and a PVC with no class.
#    Watch the PVC get "standard" and ignore your PV. Fix it two ways (class "manual" on both, or "" on PVC).

# C. Released PV (5 min): PV with Retain, bind it, delete PVC → Released. New PVC stays Pending.
#    Remove claimRef → Bound.

# D. Default SC swap (5 min): drills 3.2. `k get sc` must show exactly one (default).

# E. WaitForFirstConsumer (5 min): PVC on "standard" → Pending + event. Create pod → Bound.
#    Which node did the PV land on? k get pv -o yaml | grep -A5 nodeAffinity

# F. StatefulSet (10 min): section 6. Scale 2→1→2, confirm db-1 gets the same PVC and its /data/me file back.

# G. break.sh 9 again (5 min), now with full understanding of why storageClassName is immutable.
```

---
← [[04-security]] · [[00 Home|🏠 Home]] · [[06-networking]] →
