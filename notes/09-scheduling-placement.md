# 09: Pod placement: taints, tolerations, nodeSelector, affinity, anti-affinity, topology spread, nodeName

Domain: **Workloads & Scheduling (15%)**, and "pod Pending" in **Troubleshooting (30%)**.
PriorityClass, static pods and custom schedulers are in `02-scheduling-admission-observability.md`. Requests/limits are in `03-application-lifecycle.md` §7.

Tags: 🔥 HIGH · 🟡 MEDIUM · 🧊 LOW

---

## The big picture: two questions the scheduler asks

```
1. FILTER  "which nodes are ALLOWED?"    taints vs tolerations, nodeSelector, required affinity,
                                          enough free requests, PVC node, ports, DoNotSchedule spread
2. SCORE   "which allowed node is BEST?" preferred affinity (weights), ScheduleAnyway spread,
                                          least loaded, image already on the node...
No node passes FILTER → Pending + event "0/3 nodes are available: ..."
```

**The key idea people mix up:**
- **Taint** = the **node** says "keep away" (it repels pods).
- **Toleration** = the **pod** says "I can handle that". It **allows** the pod on the node, it does **not pull** the pod there.
- **nodeSelector / node affinity** = the **pod** says "I want to go **there**" (it attracts).
- To **dedicate** nodes to a team you need **both**: a taint (keep others out) + affinity (pull your pods in).

| Concept | 🅿️ Parking | 🍽 Restaurant | ⚽ Football | 🎬 Cinema | ✈️ Airport |
|---|---|---|---|---|---|
| Taint | "Disabled parking only" sign on a spot | "Reserved" sign on a table | "Goalkeepers only" area in training | "VIP hall" sign | "Crew only" gate |
| Toleration | the disabled badge on your dashboard: you *may* park there (but you don't have to) | your reservation: you *may* sit there | being a goalkeeper: you *may* enter | a VIP ticket: you *may* enter | a crew badge |
| NoSchedule | no new cars may park, parked ones stay | no new guests seated | — | no new tickets sold for the hall | no new flights assigned |
| NoExecute | no new cars **and** parked cars without a badge are towed away | guests without a reservation are asked to leave | players without the right license are sent off | people without VIP tickets are removed | non-crew are escorted out |
| PreferNoSchedule | "please avoid if you can" | "we'd rather not seat you here" | — | — | — |
| nodeSelector | "I only park on level 2" (exact label) | "a table by the window, nothing else" | — | "seat in row F only" | — |
| Node affinity required | "level 2 **or** 3, must have EV charging" (expressions) | "window or terrace, must be non-smoking" | "must play on a grass pitch" | — | "must be a gate with a jet bridge" |
| Node affinity preferred | "I'd like level 2, but anywhere is fine" | "window would be nice" | — | "middle row if possible" | — |
| Pod affinity | park **next to your friend's** car | sit **at the same table** as your friends | play next to your strike partner | 🎬 **friends sit together in one row** (like an array: side by side) | — |
| Pod anti-affinity | never park next to your ex's car | two rival families at **different tables** | don't put both goalkeepers in the same team | 🎬 **colleagues take any seats available, spread out** (like a linked list: anywhere) | don't put both pilots on the same plane |
| Topology spread | spread the fleet evenly across all car parks | spread waiters evenly across sections | spread players evenly across the pitch | fill all halls evenly | spread flights across terminals |
| nodeName | the valet ignores the office and parks the car in spot 17 himself | you walk past the host and sit down yourself | — | you sit in a seat without asking the cashier | — |

---

## 1. Taints and tolerations 🔥 HIGH

### Commands
```bash
k taint node cka-worker dedicated=infra:NoSchedule        # add  (key=value:effect)
k taint node cka-worker dedicated=infra:NoSchedule-       # remove (trailing minus)
k taint node cka-worker dedicated-                        # remove all taints with this key
k describe node cka-worker | grep -i -A3 taints
k get no -o custom-columns=NAME:.metadata.name,TAINTS:.spec.taints
```

### The 3 effects
| Effect | New pods without a toleration | Running pods without a toleration |
|---|---|---|
| `NoSchedule` | not scheduled | stay |
| `PreferNoSchedule` | avoided if possible | stay |
| `NoExecute` | not scheduled | **evicted** (after `tolerationSeconds`, if the toleration sets it) |

### Tolerations in the pod
```yaml
spec:
  tolerations:
  - key: dedicated               # operator Equal (default): key AND value must match
    operator: Equal
    value: infra
    effect: NoSchedule
  - key: gpu                     # Exists: any value of this key (no "value:" field allowed)
    operator: Exists
    effect: NoSchedule
  - key: node.kubernetes.io/unreachable
    operator: Exists
    effect: NoExecute
    tolerationSeconds: 60        # stay 60s on an unreachable node, then get evicted (default auto-added: 300)
  - operator: Exists             # empty key + Exists = tolerate EVERY taint (DaemonSets for node agents do this)
```
- `effect` omitted in a toleration = matches **all** effects for that key.
- A toleration must match **key + value + effect** (with Equal).

### Taints you'll meet in real clusters
| Taint | Who sets it | Meaning |
|---|---|---|
| `node-role.kubernetes.io/control-plane:NoSchedule` | kubeadm | keep normal pods off control planes |
| `node.kubernetes.io/not-ready:NoExecute` | node controller | node NotReady |
| `node.kubernetes.io/unreachable:NoExecute` | node controller | node lost contact |
| `node.kubernetes.io/disk-pressure:NoSchedule` | kubelet | low disk |
| `node.kubernetes.io/memory-pressure:NoSchedule` | kubelet | low memory |
| `node.kubernetes.io/unschedulable:NoSchedule` | `k cordon` | cordoned |

**Exam pattern: "run a pod on the control plane node"** → add the toleration for `node-role.kubernetes.io/control-plane` (operator Exists, effect NoSchedule) **and** a `nodeSelector: {node-role.kubernetes.io/control-plane: ""}` (or `nodeName`). The toleration alone doesn't send it there.

⚠️ Traps:
- Typing the taint as `key:value=effect` → error. It's `key=value:effect`.
- The pending message shows it: `1 node(s) had untolerated taint {dedicated: infra}`.
- Removing a taint from the control plane "to make it work" when the task didn't ask = changing the cluster beyond the task.

---

## 2. nodeSelector 🔥 HIGH

The simplest way to attract: exact label match, **AND** between labels.
```bash
k label node cka-worker2 disk=ssd
k label node cka-worker2 disk=hdd --overwrite
k label node cka-worker2 disk-                    # remove the label
k get no --show-labels ; k get no -l disk=ssd
```
```yaml
spec:
  nodeSelector:
    disk: ssd
    kubernetes.io/hostname: cka-worker2           # built-in label: pin to one node
```
Built-in node labels worth knowing: `kubernetes.io/hostname`, `kubernetes.io/os`, `kubernetes.io/arch`, `node-role.kubernetes.io/control-plane`, `topology.kubernetes.io/zone`, `topology.kubernetes.io/region`.

---

## 3. Node affinity 🔥 HIGH

nodeSelector with superpowers: **operators**, **OR**, and **soft** preferences.

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:   # HARD rule (filter)
        nodeSelectorTerms:                              # terms are OR'ed
        - matchExpressions:                             # expressions inside one term are AND'ed
          - {key: disk, operator: In, values: [ssd, nvme]}
          - {key: kubernetes.io/arch, operator: In, values: [amd64]}
        - matchExpressions:                             # OR this term
          - {key: special, operator: Exists}
      preferredDuringSchedulingIgnoredDuringExecution:  # SOFT rule (score)
      - weight: 80                                      # 1-100, higher = more important
        preference:
          matchExpressions:
          - {key: zone, operator: In, values: [zone-a]}
      - weight: 20
        preference:
          matchExpressions:
          - {key: cheap, operator: Exists}
```

| Operator | Meaning |
|---|---|
| `In` / `NotIn` | label value in / not in the list |
| `Exists` / `DoesNotExist` | key present / absent (no `values`) |
| `Gt` / `Lt` | value greater / less than (integer as a string) |

`NotIn` and `DoesNotExist` give you **node anti-affinity** ("never on nodes with `gpu`").

**"IgnoredDuringExecution"** = rules are checked only at scheduling time. Remove the label from the node later → running pods **stay**. 🅿️ Your car stays parked even if they repaint the "level 2" sign.

⚠️ Traps:
- Indentation: `nodeSelectorTerms` → list → `matchExpressions` → list. Copy from docs: **"Assign Pods to Nodes using Node Affinity"**.
- `nodeSelector` and `nodeAffinity` together → **both** must match.
- `k explain pod.spec.affinity.nodeAffinity --recursive` if you forget a field name.

---

## 4. Pod affinity and pod anti-affinity 🟡 MEDIUM (anti-affinity "one per node" is 🔥)

### The cinema analogy (array vs linked list) 🎬
- **Pod affinity = friends going to the cinema together:** they want seats **side by side in the same row** (like an **array**: contiguous). "Put my pod on a node (row) where a `cache` pod already sits."
- **Pod anti-affinity = colleagues who each just want a seat:** any free seats, **spread out** across the hall (like a **linked list**: anywhere, connected only by the booking). "Never put two `web` pods on the same node", so one node crash doesn't kill all replicas.
- **topologyKey = what counts as "together"**: the same **seat row** (`kubernetes.io/hostname` = same node) or the same **cinema building** (`topology.kubernetes.io/zone` = same zone).

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: web}
spec:
  replicas: 3
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      affinity:
        podAntiAffinity:                                   # "max one web pod per node"
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels: {app: web}                      # pods to stay AWAY from (here: my own replicas)
            topologyKey: kubernetes.io/hostname            # "same place" = same node
        podAffinity:                                       # "be near a cache pod"
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:                               # ⚠️ preferred → wrapped in podAffinityTerm
              labelSelector:
                matchLabels: {app: cache}
              topologyKey: kubernetes.io/hostname
              # namespaces: [other-ns]                     # default: the pod's own namespace
      containers:
      - name: nginx
        image: nginx:1.27
```
With **required** anti-affinity, 3 replicas and only 2 schedulable workers → the 3rd pod is **Pending** (`didn't match pod anti-affinity rules`). Use **preferred** if "best effort" is enough.

⚠️ Traps:
- Pod affinity matches **pod labels**, node affinity matches **node labels**. Different selectors.
- `topologyKey` is **required** and must be a node label that exists.
- `required` = `labelSelector` + `topologyKey` directly. `preferred` = `weight` + `podAffinityTerm: {...}`.

---

## 5. Topology spread constraints 🟡 MEDIUM

### Analogy
🅿️ A taxi company with 3 car parks: "the number of our taxis in any two car parks may differ by **at most 1**" (`maxSkew: 1`). 6 taxis → 2/2/2. Not 4/1/1.

```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1                               # allowed difference between the fullest and emptiest domain
    topologyKey: kubernetes.io/hostname      # domain = node (or topology.kubernetes.io/zone)
    whenUnsatisfiable: DoNotSchedule         # hard (Pending if it would break the rule) | ScheduleAnyway (soft)
    labelSelector:
      matchLabels: {app: web}                # which pods are counted
```
Difference from anti-affinity: anti-affinity = "**never** two on one node" (hard limit of 1 per node). Spread = "**evenly**", several per node allowed.

---

## 6. nodeName: skipping the scheduler 🟡 MEDIUM

```yaml
spec:
  nodeName: cka-worker        # the scheduler is never involved; the kubelet on that node runs it directly
```
- 🍽 You walk past the host and sit at table 7 yourself.
- Ignores nodeSelector/affinity and **NoSchedule** taints (no scheduler checks them). The kubelet still checks resources (`OutOfcpu`/`OutOfmemory`), and **NoExecute** taints still evict it.
- Useful when **the scheduler is broken** (`break.sh 1`): a pod with `nodeName` still runs. A good sanity check and a good exam question.
- Can't be changed on an existing pod → recreate it.

---

## 7. DaemonSets and placement 🟡 MEDIUM

- The DaemonSet controller places one pod per matching node and automatically adds tolerations for `not-ready`, `unreachable`, `disk-pressure`, `memory-pressure`, `unschedulable`...
- It does **not** auto-tolerate the control-plane taint → to run on control planes too:
```yaml
tolerations:
- key: node-role.kubernetes.io/control-plane
  operator: Exists
  effect: NoSchedule
```
- Limit to some nodes with `nodeSelector` / node affinity in the pod template.
- No `k create ds`: `k create deploy x --image=... $do > ds.yaml`, change `kind: DaemonSet`, delete `replicas`, `strategy`, `status`.

---

## 8. PodDisruptionBudget 🟡 MEDIUM

### Analogy
⚽ "The club must always have **at least 2 goalkeepers available**." During voluntary disruptions (drain, upgrade), the league won't let you sell a goalkeeper if that would leave fewer than 2.

```bash
k create pdb web-pdb --selector=app=web --min-available=2      # or --max-unavailable=1
k get pdb                                                     # ALLOWED DISRUPTIONS column
```
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: web-pdb}
spec:
  minAvailable: 2          # or maxUnavailable: 1 (not both)
  selector:
    matchLabels: {app: web}
```
Only **voluntary** evictions (drain, eviction API) respect it. A node crash doesn't care.

---

## 9. "Why is my pod Pending?" decoder 🔥 HIGH

`k describe po x` → Events → `0/3 nodes are available: ...`

| Message part | Meaning → fix |
|---|---|
| `Insufficient cpu` / `Insufficient memory` | requests too big for free capacity → lower requests / scale down others |
| `had untolerated taint {key: value}` | add a toleration or remove the taint (if the task allows) |
| `didn't match Pod's node affinity/selector` | node labels vs nodeSelector/affinity → label the node or fix the pod |
| `didn't match pod anti-affinity rules` | too few nodes for required anti-affinity → preferred, or more nodes |
| `didn't match pod topology spread constraints` | `DoNotSchedule` blocks → `ScheduleAnyway` or more domains |
| `node(s) were unschedulable` | cordoned → `k uncordon` |
| `pod has unbound immediate PersistentVolumeClaims` | PVC issue → `05-storage.md` §8 |
| `node(s) had volume node affinity conflict` | PV is tied to another node |
| `didn't have free ports for the requested pod ports` | `hostPort` already used |
| `Preemption is not helpful for scheduling` | info only, still the reasons above |
| **no events at all** | scheduler down, or `schedulerName` → `02-scheduling-admission-observability.md` §2, `break.sh 1` |

---

## 10. Self-check

1. A node has taint `gpu=true:NoSchedule`. A pod tolerates it. Will it land on that node?
2. Difference between NoSchedule and NoExecute for a pod already running?
3. You add `NoExecute` to a node. A pod tolerates it with `tolerationSeconds: 30`. What happens?
4. Two `nodeSelectorTerms`: AND or OR? Two `matchExpressions` in one term?
5. Which operator means "nodes without label X"?
6. You remove the label a running pod's required node affinity depends on. What happens?
7. 3 replicas, required anti-affinity on hostname, 2 workers + 1 tainted control plane. Result?
8. Pod with `nodeName: node01` and node01 has a NoSchedule taint it doesn't tolerate. Runs?
9. How do you run a pod on the control plane node (and only there)?
10. `0/3 nodes are available: 3 Insufficient memory`. Two fixes?
11. Make a DaemonSet run on control-plane nodes too.
12. Topology spread vs pod anti-affinity: one sentence each.

<details><summary>Answers</summary>

1. Not guaranteed: a toleration only **allows** it. Add affinity/nodeSelector to pull it there.
2. NoSchedule: it stays. NoExecute: it's evicted (unless it tolerates the taint).
3. It stays 30 seconds, then gets evicted.
4. Terms = OR. Expressions within one term = AND.
5. `DoesNotExist` (or `NotIn` for specific values).
6. Nothing: IgnoredDuringExecution. It stays.
7. 2 pods Running (one per worker), 1 Pending.
8. Yes. With nodeName the scheduler (which enforces NoSchedule) is skipped. (A NoExecute taint would evict it.)
9. Toleration for `node-role.kubernetes.io/control-plane:NoSchedule` + `nodeSelector: {node-role.kubernetes.io/control-plane: ""}` (or `kubernetes.io/hostname: <cp>`).
10. Lower the memory requests, or free capacity (scale something down / add a node).
11. Add a toleration for `node-role.kubernetes.io/control-plane` with operator Exists, effect NoSchedule.
12. Spread = keep counts even across domains (several per node OK). Anti-affinity = never together in the same domain.
</details>

---

## 11. Mini-drills in your kind lab (≈45 min)

```bash
# A. Dedicated nodes (10 min): taint cka-worker team=a:NoSchedule + label team=a.
#    Deployment "a" (3 replicas) must run ONLY on cka-worker → toleration + nodeSelector. Verify with -o wide.
#    Deployment "b" without anything → never lands on cka-worker. Clean up the taint/label.

# B. Effects (5 min): pods running on cka-worker2, add a NoExecute taint, watch them leave (k get po -o wide -w).
#    Add one pod with tolerationSeconds: 30 and time it. Remove the taint.

# C. Node affinity (10 min): required In [ssd,nvme] + preferred weight 80 zone=a. Label nodes differently and
#    see where pods go. Try NotIn / DoesNotExist.

# D. One per node (5 min): deployment 3 replicas, required anti-affinity on hostname → 2 Running, 1 Pending.
#    Read the event. Change to preferred → 3 Running.

# E. Control plane pod (5 min): question 9. Verify it's on cka-control-plane.

# F. Scheduler down (5 min): break.sh 1 → a normal pod stays Pending, a pod with nodeName: cka-worker runs. Then fix it.

# G. Pending decoder (5 min): create pods that are Pending for 4 different reasons (big request, taint, selector, PVC)
#    and read each message.
```
