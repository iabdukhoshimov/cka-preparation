# 02: Scheduling, admission and observability (reviewed and corrected)

This is the "Part 2" guide from our other session, checked line by line. Cut-off lines are completed, mistakes are fixed (marked **🔧 FIX**), and every topic has analogies from several themes.
Each section is tagged with how likely it is to show up on the CKA v1.37 exam:

- 🔥 **HIGH:** shows up a lot. Must be fast.
- 🟡 **MEDIUM:** possible. Know the steps.
- 🧊 **LOW:** rare on the CKA (more of a course/CKS topic). Know the idea, don't spend hours on it.

Your kind lab names: control plane node `cka-control-plane`, workers `cka-worker` and `cka-worker2`.
"SSH" into a node with `./cluster/ssh.sh cp|w1|w2`. The API server pod is `kube-apiserver-cka-control-plane`.

---

## The big picture in one story

| Step | 🚗 Car garage | ⚽ Football match | 🎬 Cinema |
|---|---|---|---|
| AuthN | show your driver's license | player shows ID at the stadium gate | show your ticket |
| AuthZ (RBAC) | are you on the allowed list? | are you on today's squad list? | does your ticket cover *this* hall? |
| Mutating admission | prep station adds a parking permit | kit man gives you shin guards you forgot | usher gives you 3D glasses |
| Validating admission | inspector: pass/reject | referee checks studs and jewellery: play or leave | security: no outside food, rejected |
| etcd | the car is now registered in the garage book | the name is on the official team sheet | the seat is marked as sold in the system |
| Scheduler | dispatcher picks a parking spot | coach picks your position | system assigns your seat |
| Priority | ambulance goes first | captain/star player gets picked first | VIP ticket holders seated first |
| kubelet | the valet who actually parks the car | the player actually on the pitch | the usher who walks you to the seat |
| Static pod | the car the valet parks without asking the office | groundskeeper always on the field, not on the team sheet | the projectionist always in the booth, never ticketed |
| top / logs | dashboard gauges / black box recorder | live stats / match replay | live seat count / CCTV recording |

---

## 1. PriorityClass 🔥 HIGH

### Analogies
- 🚑 **Car:** an ambulance with its siren on. Cars pull over, and if there's no room, some get pushed off the road (**preemption**).
- ⚽ **Football:** the squad is full (the node is full). The star signing arrives, and the coach drops a bench player to make room.
- 🎉 **Friends' party:** the house is full. Your best friend arrives, so someone you barely know is asked to leave.
- 🎬 **Cinema:** VIP ticket holders enter first. With `preemptionPolicy: Never`, a VIP waits at the front of the line but never kicks anyone out of their seat.

### Facts
- It's **cluster-scoped** (no namespace), and it gives pods a priority **number**. Higher = more important.
- It affects **two things**: (1) scheduling queue order, and (2) **preemption**, meaning lower-priority pods are evicted when nothing fits.

| Value | Who |
|---|---|
| 2000001000 | `system-node-critical` (built in) |
| 2000000000 | `system-cluster-critical` (built in) |
| ≤ 1000000000 | your classes (1 billion max) |
| 0 | pods with no class, unless some class has `globalDefault: true` |

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: ambulance              # must NOT start with "system-"
value: 1000000
globalDefault: false           # true = pods without a class get this one. Only ONE class may be default
preemptionPolicy: PreemptLowerPriority   # or Never = jump the queue but never evict anyone
description: "Critical apps"
---
apiVersion: v1
kind: Pod
metadata:
  name: critical-app
spec:
  priorityClassName: ambulance
  containers:
  - name: nginx
    image: nginx:1.27
```

```bash
k get pc
k create priorityclass high --value=1000 --description="high prio" [--global-default] [--preemption-policy=Never]
k get po -o custom-columns=NAME:.metadata.name,PRIO:.spec.priority,CLASS:.spec.priorityClassName
```

### Commonly reported exam pattern
> "Create PriorityClass `high-priority` with a value **one less than the highest existing user-defined class**, then patch deployment X to use it."

```bash
k get pc --sort-by=.value          # ignore system-* classes, take the highest user value, subtract 1
k create pc high-priority --value=<that-1> --description=...
k -n <ns> patch deploy X -p '{"spec":{"template":{"spec":{"priorityClassName":"high-priority"}}}}'
k -n <ns> rollout status deploy X  # pods are recreated with the new class
```
⚠️ Put `priorityClassName` in the **pod template** (`spec.template.spec`), not in the Deployment's top-level `spec`.

---

## 2. Multiple schedulers 🧊 LOW (but the Pending trap is 🔥)

### Analogies
- 🚗 **Car:** a second dispatcher who only handles sports cars. Each car has a sticker (`schedulerName`).
- ⚽ **Football:** two coaches. Each player's shirt says which coach picks their position. If that coach never shows up, **the player sits in the tunnel forever** (Pending).
- 🍽 **Restaurant:** you asked for waiter "Ali" specifically. Ali is off today, so nobody seats you.

### Facts
- The pod sets `spec.schedulerName: my-scheduler`. If no scheduler with that name is running → **Pending forever, with no scheduling event.**
- `k describe po` shows **no "FailedScheduling" event**. That missing event is your hint.

```yaml
# my-scheduler-config.yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
- schedulerName: my-scheduler
leaderElection:
  leaderElect: false
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-scheduler
  namespace: kube-system
spec:
  serviceAccountName: my-scheduler
  containers:
  - name: my-scheduler
    image: registry.k8s.io/kube-scheduler:v1.37.0   # 🔧 FIX: use the SAME version as your cluster (the paste said v1.31.0)
    command:
    - kube-scheduler
    - --config=/etc/kubernetes/my-scheduler/my-scheduler-config.yaml
    volumeMounts:
    - name: config
      mountPath: /etc/kubernetes/my-scheduler
  volumes:
  - name: config
    configMap:
      name: my-scheduler-config
```

```bash
# Find the right image: copy it from the default scheduler
k -n kube-system get po kube-scheduler-cka-control-plane -o jsonpath='{.spec.containers[0].image}'

k -n kube-system create cm my-scheduler-config --from-file=my-scheduler-config.yaml
# 🔧 FIX (missing in the paste): the ServiceAccount needs permissions, or the scheduler crashes / can't bind
k -n kube-system create sa my-scheduler
k create clusterrolebinding my-scheduler-as-kube-scheduler   --clusterrole=system:kube-scheduler   --serviceaccount=kube-system:my-scheduler
k create clusterrolebinding my-scheduler-as-volume-scheduler --clusterrole=system:volume-scheduler --serviceaccount=kube-system:my-scheduler

k get events -o wide      # SOURCE column shows "my-scheduler"
k -n kube-system logs my-scheduler
```

---

## 3. Static pods 🔥 HIGH

### Analogies
- 🚗 **Car:** the engine computer (ECU) starts the engine when you turn the key. It doesn't call head office for permission.
- ⚽ **Football:** the groundskeeper. They're always on the field, the referee (API server) didn't pick them, and the referee only sees them on a "staff list" (the **mirror pod**). Cross them off the list and they're still there. **To remove them, end their contract (delete the file).**
- 🏠 **Friends:** the roommate whose name is on the lease. You can't kick them out of the group chat to make them leave. You have to change the lease.
- 🎬 **Cinema:** the projectionist in the booth. They're not on the ticket system, and they start whenever the building opens.

### Facts
- The **kubelet** watches a folder, usually `/etc/kubernetes/manifests`, and runs every manifest it finds there. There's **no scheduler and no controller**.
  - Add a file → the pod starts. Edit it → the pod is recreated. Delete it → the pod is gone.
- The API server shows a read-only **mirror pod** named `<pod>-<nodename>`, for example `kube-apiserver-cka-control-plane`.
- `k delete pod` on a static pod → **it comes right back**. Delete the **file** instead.
- On kubeadm clusters, **etcd, kube-apiserver, kube-controller-manager and kube-scheduler are static pods**. "Fix the control plane" almost always means "fix a file in `/etc/kubernetes/manifests/`".

### Find the static pod path (always check, never assume)
```bash
# on the node:
ps aux | grep kubelet | grep -o -- '--config=[^ ]*'      # usually /var/lib/kubelet/config.yaml
grep -i staticPodPath /var/lib/kubelet/config.yaml
```

### Create one, exam style
```bash
# 🔧 FIX: worker nodes usually have NO working kubectl/kubeconfig.
# Generate the YAML on the machine where kubectl works, then put it on the node.
k run static-busybox --image=busybox:1.36 $do --command -- sleep 1000 > static-busybox.yaml
cat static-busybox.yaml        # copy it
ssh node01                     # lab: ./cluster/ssh.sh w1
vi /etc/kubernetes/manifests/static-busybox.yaml   # paste it (or use the path from staticPodPath)
exit
k get po -A | grep static-busybox     # shows up as static-busybox-node01
```

### Is a pod static?
```bash
k get po <name> -n <ns> -o jsonpath='{.metadata.ownerReferences[0].kind}'
# Node → static | ReplicaSet / DaemonSet / StatefulSet / Job → normal controller pod
```

⚠️ Traps:
- "Static pod on node01" → you must **SSH to node01**, and `exit` back afterwards.
- 🔧 **Never keep a backup copy inside `/etc/kubernetes/manifests/`.** The kubelet will try to run it too. Back up with `cp kube-apiserver.yaml /root/kube-apiserver.yaml.bak`.

---

## 4. Scheduler profiles and the scheduling framework 🧊 LOW

### Analogies
- 🚗 **Car:** one dispatcher with two rulebooks. "Spread cars across lots" vs "fill one lot first".
- ⚽ **Football:** one coach with two tactics boards (4-4-2 vs 3-5-2). The player's shirt says which board to use.
- 🎬 **Cinema seating:**
  - **queueSort:** who's first in line (VIPs)
  - **filter:** which seats are even possible (hall open? wheelchair access? 18+ hall?)
  - **score:** which of those seats is best (middle row, close to friends)
  - **bind:** print the ticket

```
Pod → [queueSort] → [preFilter → filter → postFilter] → [preScore → score] → [reserve → permit → preBind → bind → postBind]
       who first?     which nodes CAN fit?                 rank the nodes        commit to a node
```

| Phase | Example plugins | Question it answers |
|---|---|---|
| queueSort | PrioritySort | who gets scheduled first |
| filter | NodeResourcesFit, NodeName, NodeUnschedulable, TaintToleration, NodeAffinity, VolumeBinding | can it run here at all? |
| postFilter | DefaultPreemption | nothing fits → evict lower priority? |
| score | NodeResourcesFit, ImageLocality, TaintToleration, NodeAffinity, PodTopologySpread | which node is best? |
| bind | DefaultBinder | write `spec.nodeName` |

Multiple profiles in one scheduler:
```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
- schedulerName: default-scheduler
- schedulerName: no-scoring-scheduler
  plugins:
    preScore: {disabled: [{name: '*'}]}
    score:    {disabled: [{name: '*'}]}
```
Multiple schedulers = **separate processes**, which can race for the same node. Profiles = **one process**, no races, easier to run.

---

## 5. Admission controllers 🟡 MEDIUM (editing the API server flags is 🔥)

### Analogies
- 🚗 **Car garage:** ID check → allowed list → **car inspection** (bald tyres? rejected. No permit? Here's a default one. Garage full? Rejected.) → registered.
- ⚽ **Football:** RBAC says "you're in the squad". Admission is the referee checking your **kit** before you step on the pitch. The kit man adds missing shin guards (mutating), then the referee says yes or no (validating).
- ✈️ **Airport:** passport (AuthN) → boarding pass for *this* flight (AuthZ) → staff re-tag your bag (mutating) → security scanner: allowed or not (validating) → you board (etcd).

**RBAC looks at *who* you are and *what action* you want. Admission looks at the *object itself* and can change it.**

### Request flow (memorize this)
```
kubectl → AuthN → AuthZ (RBAC) → Mutating admission → Schema validation → Validating admission → etcd
```

| Plugin | Type | What it does | 🚗 / ⚽ |
|---|---|---|---|
| NamespaceLifecycle | validating | rejects objects in non-existent/terminating namespaces; protects `default`, `kube-system`, `kube-public` from deletion | can't park in a garage being demolished |
| NamespaceAutoProvision | mutating | **off by default** 🔧 (the paste said "deprecated"; it's an old plugin you rarely want, and the deprecated one is `NamespaceExists`). Creates a missing namespace | builds the garage when you arrive |
| LimitRanger | **both** 🔧 | mutating: adds default requests/limits. Validating: rejects pods outside min/max | default speed limiter fitted + max speed check |
| ResourceQuota | validating | rejects if the namespace quota would be exceeded | garage full / squad limit of 25 players |
| ServiceAccount | mutating | adds the default SA + token volume | everyone gets a visitor badge |
| DefaultStorageClass | mutating | PVC without a class → gets the default class | default fuel type |
| AlwaysPullImages | mutating | sets `imagePullPolicy: Always` | fresh inspection every visit |
| NodeRestriction | validating | a kubelet may only modify its own Node object and its own pods | a player can only change their own shirt |
| PodSecurity | validating | enforces Pod Security Standards (privileged/baseline/restricted) via namespace labels | no dangerous boots allowed |

### See what's enabled
```bash
# what is set explicitly (on the control plane node):
grep admission /etc/kubernetes/manifests/kube-apiserver.yaml
ps -ef | grep kube-apiserver | tr ' ' '\n' | grep admission

# the built-in defaults (pod name differs per cluster; in your lab it's kube-apiserver-cka-control-plane):
k -n kube-system exec kube-apiserver-cka-control-plane -- kube-apiserver -h | grep -A2 'enable-admission-plugins'
```

### Enable or disable a plugin (exam task)
```bash
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak   # backup OUTSIDE the manifests dir
vi /etc/kubernetes/manifests/kube-apiserver.yaml
#   - --enable-admission-plugins=NodeRestriction,NamespaceAutoProvision
#   - --disable-admission-plugins=DefaultStorageClass
# save → the kubelet recreates the static pod (30–90 s)

watch crictl ps | grep apiserver           # on the node, while kubectl is unavailable
crictl ps -a | grep apiserver              # Exited? →
crictl logs <container-id>                 # the error is usually a typo in a flag
ls /var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/   # if the container doesn't even start
journalctl -u kubelet | tail -30           # if the manifest YAML itself is invalid
```
🔑 **It's ONE flag with a comma-separated list.** Add to the existing line. Don't add a second `--enable-admission-plugins` line.

---

## 6. Validating and mutating webhooks 🧊 LOW (on the CKA)

### Analogies
- 🚗 **Car:** mutating = the prep station (adds a seatbelt, sets tyre pressure to 32 PSI). Validating = the final inspector (only PASS/REJECT, changes nothing).
- ⚽ **Football:** mutating = the kit man (fixes your kit). Validating = the referee (only allows you on or not).
- 🎬 **Cinema:** mutating = the usher hands you 3D glasses. Validating = the guard checks the age on your ID for the 18+ film.

**Order: mutating FIRST, then validating.** The inspector must see the *final* version. If validation ran first, a later mutation could make the object invalid again without anyone checking.

How it works:
1. The API server POSTs an `AdmissionReview` (JSON) over **HTTPS** to your webhook Service.
2. Validating reply: `allowed: true/false` + a message. Mutating reply: `allowed: true` + a base64-encoded **JSONPatch**.

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration        # ValidatingWebhookConfiguration looks the same; path is usually /validate
metadata:
  name: demo-webhook
webhooks:
- name: webhook-server.webhook-demo.svc
  clientConfig:
    service: {name: webhook-server, namespace: webhook-demo, path: "/mutate"}
    caBundle: <base64 CA cert>            # so the API server trusts the webhook's TLS cert
  rules:
  - operations: ["CREATE"]
    apiGroups: [""]
    apiVersions: ["v1"]
    resources: ["pods"]
  admissionReviewVersions: ["v1"]
  sideEffects: None
  failurePolicy: Fail                     # Fail = reject if the webhook is down | Ignore = let it through
```
🔥 Troubleshooting angle: "Pods can't be created in any namespace" + a webhook with `failurePolicy: Fail` whose Service is down → that's the cause. `k get validatingwebhookconfigurations,mutatingwebhookconfigurations`
💡 **ValidatingAdmissionPolicy** (GA since 1.30): validation rules written in CEL directly in YAML, with no webhook server. Know that it exists.

---

## 7. Logging and monitoring 🔥 HIGH

### Analogies
- 🚗 **Car:** metrics-server = the dashboard (speed and fuel **right now**, no history). Logs = the black box recorder. Prometheus/Grafana = a fleet tracking system (history; not deep on the CKA).
- ⚽ **Football:** `top` = the live stats on the TV screen (possession right now). `logs` = the match replay. `logs --previous` = the replay of the **last** match, the one you lost.
- 🏥 **Hospital:** `top` = the heart-rate monitor. `logs` = the patient's chart. `journalctl -u kubelet` = the nurse's notebook for the whole ward.

### Monitoring
- The kubelet's built-in **cAdvisor** collects container CPU and memory → **metrics-server** scrapes every kubelet → `k top` (in memory only, no history).
- 🔧 In the exam metrics-server is normally **already installed**, and GitHub isn't reachable anyway. On kind it needs `--kubelet-insecure-tls` (your `cluster/up.sh` already handles that).

```bash
k top node
k top pod -A --sort-by=memory
k top pod -n prod --sort-by=cpu
k top pod --containers
# Classic task: "pod using the most CPU in ns X → write its name to /opt/answer.txt"
k top pod -n X --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > /opt/answer.txt
cat /opt/answer.txt          # ALWAYS check the file
```

### App logs
```bash
k logs mypod                  # -c is REQUIRED when the pod has several containers
k logs mypod -c sidecar
k logs mypod --all-containers
k logs mypod --previous       # 🔥 the crashed attempt (CrashLoopBackOff)
k logs mypod -f --tail=50 --since=1h
k logs -l app=web             # 🔧 only the last 10 lines PER POD by default; add --tail=-1 for everything
k logs deploy/web             # 🔧 picks ONE pod of the deployment, not all of them
k logs mypod | grep -i error > /opt/errors.txt
```

### Node and control-plane logs (troubleshooting)
```bash
systemctl status kubelet ; journalctl -u kubelet -n 50 --no-pager   # kubelet = systemd service, not a pod
k -n kube-system logs kube-apiserver-cka-control-plane              # if the API works
crictl ps -a | grep -E 'apiserver|etcd|scheduler|controller'        # if the API is DOWN
crictl logs <container-id>
ls /var/log/pods/  /var/log/containers/
```

---

## 8. Self-test answers (from the paste)

1. **`schedulerName: fast-scheduler`, pod Pending:** no scheduler named `fast-scheduler` is running (or it's crashing, or missing RBAC). There's no FailedScheduling event, because nobody even tried. Fix: start that scheduler, or remove/change `schedulerName`. That field can't be edited on a running pod, so recreate it with `k replace --force`.
2. **`etcd-controlplane` came back after delete:** it's a static pod, and the kubelet recreates it from `/etc/kubernetes/manifests/etcd.yaml`. To really remove it, move the file out of that folder. (On a real control plane that kills the cluster's datastore. Don't do it in the exam unless asked.)
3. **Mutating runs first,** so validating sees the final object. Otherwise a later mutation could make an approved object invalid.
4. **NamespaceAutoProvision:** add it to the existing `--enable-admission-plugins=` flag in `/etc/kubernetes/manifests/kube-apiserver.yaml`. The kubelet notices the change and recreates the API server pod, so the API is unavailable for about 30–90 s. Then, for example, `k run x --image=nginx -n doesnotexist` creates the namespace automatically.
5. **`k logs <pod> --previous`** (`-p`).
6. **`preemptionPolicy: Never`:** the pod still sorts ahead of lower-priority pods in the scheduling queue, but it never evicts running pods to make room. It waits until space frees up.

---

## 9. Mini-drills in your kind lab (≈45 min total)

```bash
# A. Static pod on a worker (10 min)
./cluster/ssh.sh w1
grep staticPodPath /var/lib/kubelet/config.yaml
cat > /etc/kubernetes/manifests/static-web.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: static-web}
spec:
  containers: [{name: web, image: nginx:1.27}]
EOF
exit
k get po -A | grep static-web           # static-web-cka-worker
k delete po static-web-cka-worker       # comes back!  → then rm the file on the node

# B. PriorityClass "one less than highest" (5 min): create pc a=1000, b=5000, then do the exam pattern from section 1

# C. Pending-scheduler trap (5 min)
k run lost --image=nginx $do > lost.yaml; sed -i '/^spec:/a\  schedulerName: nobody' lost.yaml; k apply -f lost.yaml
k describe po lost | tail -5            # no events → that's the clue. Fix it with k replace --force

# D. Admission plugin (15 min): enable NamespaceAutoProvision on cka-control-plane, then
k run auto --image=nginx -n magic-ns ; k get ns magic-ns    # then REMOVE it again and verify the API comes back

# E. Logs/top (5 min)
k top pod -A --sort-by=cpu --no-headers | head -1
k -n kube-system logs -l k8s-app=kube-dns --tail=5
```

---

## 10. What the CKA v1.37 exam is likely to ask: mapped to YOUR repo

These are task types that candidates have commonly reported since the curriculum update (Feb 2025). **They're not official and not guaranteed**, but the pattern has been consistent. The exam has about 16 tasks in 2 h.

| # | Likely task | Domain | Practice in your repo |
|---|---|---|---|
| 1 | Fix a broken control plane (wrong etcd port 2380/2381 vs **2379**, wrong cert path, bad flag in a manifest) | Troubleshooting | `troubleshoot/break.sh 4`, `8` · PRACTICE Q29 |
| 2 | Node NotReady: kubelet stopped/misconfigured | Troubleshooting | `break.sh 2`, `3` · PRACTICE Q23 |
| 3 | App broken: wrong selector/targetPort, CrashLoop, Pending | Troubleshooting | `break.sh 1`, `5`, `8`, `9` · PRACTICE Q24–Q27, Q33 |
| 4 | DNS broken / CoreDNS | Troubleshooting | `break.sh 6` · PRACTICE Q22 · drill 4.2 |
| 5 | Highest CPU/memory pod → write to a file; logs grep → file | Troubleshooting | §7 above · PRACTICE Q28, Q32 |
| 6 | Install software with **Helm** (often `helm template`/`install` with `--set`, CRDs disabled, a specific version) | Architecture | drill 1.4 |
| 7 | **CRDs:** list cert-manager/other CRDs to a file, `k explain <crd>.spec.<field>` to a file | Architecture | drill 1.6 |
| 8 | **Install a CNI** from a manifest/operator. Pick one that supports NetworkPolicy (**Calico**, not Flannel) | Architecture | references/cka-certification-guide (CNI notes) |
| 9 | **CRI prep:** `dpkg -i cri-dockerd*.deb`, `systemctl enable --now`, sysctl `net.ipv4.ip_forward=1`, `net.bridge.bridge-nf-call-iptables=1` persisted in `/etc/sysctl.d/` | Architecture | Killercoda (needs a VM-like node) |
| 10 | RBAC: SA + Role + binding, verify with `auth can-i` | Architecture | drills 1.1, 1.2 · PRACTICE Q1, Q2 |
| 11 | kubeadm upgrade / join / etcd backup-restore | Architecture | drill 1.3, 1.7 · Killercoda |
| 12 | Kustomize | Architecture | drill 1.5 · PRACTICE Q5 |
| 13 | **Gateway API:** migrate an Ingress to a Gateway + HTTPRoute (often with TLS on the listener) | Networking | drill 4.4 (`up.sh --gateway`) |
| 14 | **NetworkPolicy:** write one, or pick the *least permissive* of several given | Networking | drill 4.3 · `break.sh 7` · PRACTICE Q20 |
| 15 | Expose a deployment with a NodePort (+ add a named containerPort) | Networking | drill 4.1 · PRACTICE Q17, Q18 |
| 16 | Ingress with path rules | Networking | PRACTICE Q21 |
| 17 | **HPA** with min/max/CPU % and a scale-down `behavior.stabilizationWindowSeconds` | Workloads | drill 2.3 · PRACTICE Q12 |
| 18 | **Native sidecar** for logs (shared emptyDir) | Workloads | drill 2.5 · PRACTICE Q32 |
| 19 | **PriorityClass** "one less than highest" + patch a deployment | Workloads | drill 2.6 · §1 above |
| 20 | **Resources:** split a node's allocatable CPU/mem evenly across N replicas (scale to 0 → edit → scale back) | Workloads | drill 2.7 · PRACTICE Q9 |
| 21 | Taints/tolerations, node affinity | Workloads | drill 2.4 · PRACTICE Q10, Q11 |
| 22 | ConfigMap change → rollout restart (for example, nginx TLS config) | Workloads | drill 2.2 · PRACTICE Q8 |
| 23 | **StorageClass:** make it the default (remove the default from the other one), `WaitForFirstConsumer` | Storage | drill 3.2 · PRACTICE Q16 |
| 24 | PVC bound to an existing PV + mount it in a deployment (e.g. "restore MariaDB data") | Storage | drill 3.1 · `break.sh 9` · PRACTICE Q14, Q15, Q34 |
| 25 | Static pod / drain-cordon / ephemeral debug container | mixed | §3 above · PRACTICE Q30, Q31 |

**Rarely seen on the CKA** (don't spend your last 2 days on them): writing webhook servers, scheduler profiles, building custom schedulers.
