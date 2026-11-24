---
tags:
  - cka/troubleshooting
---

← [[07-cluster-maintenance]] · [[00 Home|🏠 Home]] · [[09-scheduling-placement]] →

# 08: Troubleshooting and logs: the method, every pod status, control plane, nodes, networking, output to files

Domain: **Troubleshooting (30%)**, the biggest domain. It reuses everything from notes 01–07, so read this one **last**.
The `troubleshoot/break.sh` scenarios map to the sections below. Do them after reading.

Tags: 🔥 HIGH · 🟡 MEDIUM · 🧊 LOW

---

## The big picture: the car mechanic's method 🚗🔧

A good mechanic never starts by replacing parts. They go **from the outside in**:

| Step | 🚗 Mechanic | ✈️ Airport ops | Kubernetes |
|---|---|---|---|
| 1. Symptom | "the car won't start" | "flight delayed" | `k get po -A`, `k get no` (what's red?) |
| 2. Dashboard lights | check the warning lights | check the departures board status | `k describe` → **Events** at the bottom |
| 3. Black box | read the error codes from the ECU | read the flight recorder | `k logs [-p] [-c]` |
| 4. Under the hood | open the bonnet, check the engine | go onto the apron, check the plane | `ssh node` → `systemctl status kubelet`, `journalctl -u kubelet`, `crictl ps -a`, `crictl logs` |
| 5. Blueprint | compare with the factory manual | compare with the flight plan | compare the manifest/config with what it *should* be (`/etc/kubernetes/manifests`, `/var/lib/kubelet/config.yaml`) |
| 6. Fix + test drive | fix, then drive around the block | fix, then a test flight | apply the fix, **verify** (`get`, `curl`, `auth can-i`, `rollout status`) |

**Which layer is broken?** (from [[01-core-objects]] §0)
```
kubectl ──▶ API server ──▶ etcd
                 │
   controller-manager (Deployment → RS → Pods)   ← no pods created at all?
   scheduler          (Pod → node)               ← Pending, no node?
   kubelet + runtime  (actually run containers)  ← ContainerCreating / ImagePull / CrashLoop?
   your app / config                              ← CrashLoop, not Ready, wrong port?
   network (CNI, kube-proxy, DNS, NetworkPolicy)  ← runs fine but unreachable?
```

---

## 1. Pod status → cause → fix 🔥 HIGH

> [!example]+ Analogies
> - 🍽 **Restaurant order tracking:**
>   - `Pending` = the order is taken, but **no table/chef is assigned** (scheduler can't place it).
>   - `ContainerCreating` = the chef is assigned but still **getting ingredients** (image pull, volumes, network).
>   - `ImagePullBackOff` = the supplier says "**that ingredient doesn't exist**" or "you're not allowed to buy it".
>   - `CrashLoopBackOff` = the chef starts cooking, **burns it**, starts again, burns it again... waiting longer each time.
>   - `CreateContainerConfigError` = the recipe card references **an ingredient label that doesn't exist** (ConfigMap/Secret/key missing).
>   - `OOMKilled` = the chef **used more counter space than allowed** and was thrown out.
>   - `Running, 0/1 Ready` = the chef is in the kitchen but **not taking orders** (readiness failing).

| Status / reason | First command | Common causes | Fix |
|---|---|---|---|
| **Pending** | `k describe po` → Events | `Insufficient cpu/memory` (requests too big), taint not tolerated, nodeSelector/affinity matches no node, PVC Pending, **no scheduler running** (no events at all!), `schedulerName` wrong | lower requests, add a toleration, fix labels, fix the PVC, fix the scheduler |
| **ContainerCreating** (long) | `k describe po` | volume can't mount (Secret/CM/PVC missing), CNI broken (`failed to setup network`), image still pulling | create the missing object, fix the CNI |
| **ErrImagePull / ImagePullBackOff** | `k describe po` | typo in image/tag, private registry without `imagePullSecrets`, no internet | fix the image name, add a pull secret |
| **CrashLoopBackOff** | `k logs po -p` | app error, wrong `command`/`args`, missing env var, **liveness probe** killing it, can't write (readOnly FS) | fix the command/env/probe |
| **CreateContainerConfigError** | `k describe po` | ConfigMap/Secret or **key** missing, `runAsNonRoot` with a root image | create it / fix the key name |
| **RunContainerError** / **StartError** | `k describe po` | command not found in image (`exec: "x": executable file not found`), bad mount | fix the command/path |
| **OOMKilled** (Last State) | `k describe po \| grep -A5 'Last State'` | memory limit too low | raise `limits.memory` |
| **Running, READY 0/1** | `k describe po` | readiness probe failing (wrong port/path) | fix the probe |
| **Completed** (restarting) | `k get po` | a Deployment runs a command that **exits** (e.g. `echo hi`) | use a long-running command, or a Job |
| **Init:CrashLoopBackOff / Init:0/1** | `k logs po -c <init>` | init container fails / waits forever (service name wrong) | fix the init command or the thing it waits for |
| **Terminating** (stuck) | `k get po -o yaml \| grep finalizers` | node gone, finalizer | `k delete po x $now` |
| **Evicted** | `k describe po` | node under disk/memory pressure | free space, `k delete po --field-selector=status.phase=Failed` |
| **Unknown / NodeLost** | `k get no` | node down | fix the node (section 4) |

### Exit codes (`k describe po` → Last State → Exit Code)
| Code | Meaning | 🚗 |
|---|---|---|
| 0 | finished normally (bad for a Deployment that should keep running) | arrived and switched off |
| 1 | application error | engine fault |
| 126 | command found but not executable | key doesn't fit the ignition |
| 127 | command **not found** | no engine installed |
| 137 | killed with SIGKILL: **OOMKilled** or liveness kill | car towed away |
| 139 | segfault | engine exploded |
| 143 | SIGTERM: graceful stop | driver switched off politely |

### Deployment exists but has 0 pods? (🔥 a different layer!)
Pods aren't failing, they're **never created**. Go **up** the chain:
```bash
k get deploy,rs -n x                 # RS exists? DESIRED vs CURRENT?
k describe rs <rs> -n x              # Events: "forbidden: exceeded quota", "failed quota: must specify requests"...
k -n kube-system get po | grep controller-manager   # no RS at all → controller-manager down (break.sh 8)
```

---

## 2. Application failures playbook 🔥 HIGH

```bash
k get po -n x -o wide                        # status, restarts, node, IP
k describe po <p> -n x | tail -20            # events
k logs <p> -n x [-c container] [-p]          # current / previous crash
k get po <p> -n x -o yaml | less             # the real spec (image, command, env, probes, volumes)
k get events -n x --sort-by=.lastTimestamp | tail -20
k exec -it <p> -n x -- sh                    # look inside (env, ls, cat config, wget localhost:port)
```
Fixing a bare pod: most of the spec can't be edited → `k edit` saves a copy in `/tmp/kubectl-edit-xxxx.yaml` → `k replace --force -f /tmp/kubectl-edit-xxxx.yaml`.
Fixing a deployment: `k edit deploy`, or `k set image/env/resources`, then `k rollout status`.

### Ephemeral debug containers 🟡
🚗 The car has no dashboard (distroless image, no shell). You plug in a **diagnostic tool** to the OBD port.
```bash
k debug -it <pod> --image=busybox:1.36 --target=<container>   # joins the process namespace of that container
k debug <pod> -it --image=busybox:1.36 --copy-to=dbg --share-processes   # debug a COPY of the pod
k debug node/cka-worker -it --image=busybox:1.36             # a pod on the node, host FS at /host (chroot /host)
```

---

## 3. Service and network failures 🔥 HIGH

Full flow in [[06-networking]] §8. The short version:

| Symptom | Check | Typical cause |
|---|---|---|
| `wget svc` hangs / no endpoints | `k get endpointslices -l kubernetes.io/service-name=svc` | selector ≠ pod labels, pods not Ready |
| connection refused | `k get svc -o yaml` (targetPort) vs the containerPort | wrong targetPort (`break.sh 5`) |
| `bad address` / `can't resolve` | `nslookup svc.ns`, CoreDNS pods | CoreDNS down (`break.sh 6`), wrong namespace, egress policy blocks 53 |
| works from one pod, not another | `k get netpol -n ns` | NetworkPolicy (`break.sh 7`) |
| NodePort doesn't answer | `k get svc` nodePort, kube-proxy pods | wrong port, kube-proxy down |
| all pods on one node unreachable | CNI pods on that node, `k get no` | CNI/calico-node crash on that node |
| Ingress/Gateway 404 | `k describe ing/httproute` | Host header, path, class, backend name/port |

---

## 4. Control plane failures 🔥 HIGH

> [!example]+ Analogies
> - ⚽ If the **front office** (API server) is closed, nobody can register anything. You can't even ask what's wrong through the usual channel → you walk to the building (ssh + crictl).
> - ⚽ If the **coach** (scheduler) is missing, players turn up but nobody picks positions → everyone sits on the bench (**Pending, and no FailedScheduling event**, because nobody even tried).
> - ⚽ If the **assistant coaches** (controller-manager) are missing, nobody notices "we only have 9 players" → Deployments with no ReplicaSets/pods, deleted pods aren't replaced, nodes going down aren't handled.
> - ⚽ If the **records book** (etcd) is unreadable, the front office collapses too → API server crashes.

| Broken component | Symptom | Where to look |
|---|---|---|
| kube-apiserver | `kubectl`: `connection refused` / `The connection to the server ... was refused` / timeout | `crictl ps -a \| grep apiserver`, `crictl logs <id>`, `/var/log/pods/kube-system_kube-apiserver-*` |
| etcd | API server crash-loops with `connection refused 127.0.0.1:2379` / TLS errors | `crictl logs <etcd-id>`, etcd.yaml (data-dir, certs) |
| kube-scheduler | new pods **Pending, no events** | `k -n kube-system get po`, `k -n kube-system logs kube-scheduler-<node>` |
| kube-controller-manager | Deployment → no RS/pods; scaling does nothing | `k -n kube-system logs kube-controller-manager-<node>` |
| kubelet on the cp | static pods all down, node NotReady | `systemctl status kubelet`, `journalctl -u kubelet` |

### The playbook when kubectl itself fails
```bash
# 1. Is it kubectl's config, or the server?
k config view --minify | grep server         # right IP and port 6443? (a 6433 typo is a classic)
# 2. On the control plane node:
ssh controlplane                             # lab: ./cluster/ssh.sh cp
crictl ps -a | grep -E 'apiserver|etcd|scheduler|controller'   # Exited / restarting?
crictl logs <container-id> 2>&1 | tail -20   # the actual error
ls /var/log/pods/                            # if crictl shows nothing (container never started)
tail /var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/*.log
journalctl -u kubelet --no-pager | tail -30  # YAML syntax error in a manifest → only kubelet logs show it
# 3. Fix the manifest
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/apiserver.bak   # backup OUTSIDE the manifests folder
vim /etc/kubernetes/manifests/kube-apiserver.yaml
# 4. Wait (30–120 s). If it doesn't restart: move the file out and back in
watch crictl ps
```

### What typically gets broken in manifests (and the error you'll read)
| Break | Error in logs |
|---|---|
| `--etcd-servers` wrong port | `dial tcp 127.0.0.1:2380: connect: connection refused` / TLS handshake error |
| cert path typo | `open /etc/kubernetes/pki/xyz.crt: no such file or directory` |
| binary name typo (`kube-schedular`) | `exec: "kube-schedular": executable file not found in $PATH` |
| unknown flag | `Error: unknown flag: --xyz` |
| wrong kubeconfig path (scheduler/KCM) | `stat /etc/kubernetes/scheduler.config: no such file` |
| YAML indentation broken | pod never appears; `journalctl -u kubelet` shows `could not process manifest file` |
| wrong `hostPath` / volume | `no such file or directory` / CrashLoop |
| wrong advertise address / probe port | probes fail → keeps restarting |

---

## 5. Worker node failures 🔥 HIGH

> [!example]+ Analogies
> - 🚗 Node `NotReady` = the car isn't reporting to the fleet office. Either the **driver** is missing (kubelet stopped), the driver has the **wrong papers** (bad kubelet config/certs), the **engine** is dead (containerd), or the **roads** are missing (CNI).
> - ✈️ A plane that stopped talking to the tower: radio off (kubelet), wrong frequency (wrong API server address/port in kubelet.conf), engines out (containerd).

```bash
k get no ; k describe no node01 | grep -A10 Conditions     # Ready=Unknown "Kubelet stopped posting node status"
ssh node01
systemctl status kubelet                    # inactive? failed? enabled?
journalctl -u kubelet -n 50 --no-pager      # THE source of truth for kubelet problems
systemctl status containerd
crictl ps                                   # does the runtime answer?
cat /var/lib/kubelet/config.yaml            # clientCAFile, staticPodPath, clusterDNS, cgroupDriver
cat /etc/kubernetes/kubelet.conf | grep server     # API server address:port
systemctl cat kubelet                       # unit + drop-ins (10-kubeadm.conf), which config/kubeconfig it uses
df -h ; free -m                             # DiskPressure / MemoryPressure
```

| journalctl / status says | Cause | Fix |
|---|---|---|
| `inactive (dead)`, `disabled` | kubelet stopped | `systemctl enable --now kubelet` (**enable**, so it survives a reboot: `break.sh 2` checks this) |
| `unable to load client CA file` | wrong `clientCAFile` | fix the path in config.yaml, restart (`break.sh 3`) |
| `failed to load kubelet config file` | config.yaml path/syntax | fix the path in the drop-in or the YAML |
| `connection refused ... :6443` / wrong port | wrong `server:` in kubelet.conf | fix it, restart |
| `failed to run Kubelet: misconfiguration: kubelet cgroup driver: "cgroupfs" is different from docker/containerd cgroup driver: "systemd"` | cgroup driver mismatch | align `cgroupDriver: systemd` + `SystemdCgroup = true` |
| `container runtime is down` / `connect: no such file ... containerd.sock` | containerd stopped | `systemctl enable --now containerd` |
| `network plugin is not ready: cni config uninitialized` | CNI missing / crashed | install/fix the CNI, check `/etc/cni/net.d` |
| kubelet binary path wrong in the unit | `status=203/EXEC` | fix `ExecStart` path (`which kubelet`), `daemon-reload` |

**After every kubelet config change:** `systemctl daemon-reload` (if you changed unit files) and `systemctl restart kubelet`. Then `exit` and `k get no` (wait ~30–60s).

---

## 6. Logs, everything you need 🔥 HIGH

> [!example]+ Analogies
> - 📼 **CCTV:** `k logs` = today's recording. `k logs -p` = **yesterday's** tape (the crashed container). If the shop burned down (pod deleted), the tapes are gone. Real clusters ship logs elsewhere (Loki/ELK); the CKA doesn't go there.
> - 🍽 **Restaurant:** app logs = the chef's notes. Events = the manager's incident book (only kept ~1 hour!). `journalctl -u kubelet` = the building manager's diary.
> - ✈️ app logs = cockpit voice recorder; events = the control tower's log; journalctl = the airport's maintenance log.

### kubectl logs
```bash
k logs p                         # single-container pod
k logs p -c sidecar              # pick a container (required if several)
k logs p --all-containers
k logs p -p                      # previous (crashed) container instance
k logs p -f --tail=50 --since=10m --timestamps
k logs deploy/web                # ONE pod of the deployment
k logs -l app=web --tail=-1 --prefix   # all matching pods; default --tail is 10 per pod with -l
k logs job/backup ; k logs p -c init-name
```
### Events
```bash
k get events -n x --sort-by=.lastTimestamp
k get events -A --field-selector type=Warning
k get events --field-selector involvedObject.name=web-abc
k events -n x --for pod/web-abc  # newer events command
```
### Node-level logs
```bash
journalctl -u kubelet -f / -n 100 / --since "10 min ago"
journalctl -u containerd
crictl ps -a ; crictl pods ; crictl logs [-f] <id> ; crictl inspect <id> | less ; crictl images
ls /var/log/pods/<ns>_<pod>_<uid>/<container>/0.log    # raw container logs on the node
ls /var/log/containers/                                 # symlinks to those, name_ns_container-id.log
```
`crictl` needs to know the runtime socket: `/etc/crictl.yaml` → `runtime-endpoint: unix:///run/containerd/containerd.sock`.

### Monitoring
```bash
k top no ; k top po -A --sort-by=cpu ; k top po -n x --sort-by=memory --containers
```
`error: Metrics API not available` → metrics-server not installed/not Ready (`k -n kube-system get deploy metrics-server`, logs: on kind it needs `--kubelet-insecure-tls`).

---

## 7. Writing answers to files: JSONPath, custom columns, sorting 🔥 HIGH

The exam loves "write X to /opt/answer.txt". Wrong format = 0 points, so **`cat` the file after writing it**.

### Analogy
📊 JSONPath is the **GPS for a JSON document**: `.items[*].metadata.name` = "for every car in the car park, read the number plate".

```bash
k get po -o wide                                         # quick look
k get po -o jsonpath='{.items[*].metadata.name}'         # space-separated names
k get po -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}'   # one per line
k get no -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'          # filter
k get po web -o jsonpath='{.spec.containers[0].image}'
k get po -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IMAGE:.spec.containers[*].image
k get po --sort-by=.metadata.creationTimestamp
k get po --sort-by=.status.containerStatuses[0].restartCount
k get pv --sort-by=.spec.capacity.storage
k get po -A --field-selector=status.phase=Running        # server-side filter
k get po -l 'app in (web,api),tier!=db'                  # label filter
k get po --no-headers | wc -l                            # counting
k get no -o json | jq -r '.items[].metadata.name'        # jq if allowed/installed
```
Common tasks:
```bash
k top po -n x --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > /opt/top-pod.txt
k logs p | grep -i error > /opt/errors.txt
k get no -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.taints}{"\n"}{end}'   # which nodes are tainted
k describe no | grep -i -E 'Name:|Taints:'
k get po -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,QOS:.status.qosClass
cat /opt/top-pod.txt          # ALWAYS
```

---

## 8. Exam tactics for troubleshooting tasks 🔥 HIGH

1. **Read the WHOLE question first.** Note the context/host to use, the namespace, the exact names, and the expected result.
2. **Snapshot before you touch anything:** `cp file /root/file.bak` (never inside `/etc/kubernetes/manifests/`).
3. Go **outside in** (the table at the top). Don't guess-edit five things at once. Change one thing, then check.
4. A control plane fix takes 1–2 minutes to show up. Use that time to **flag and move on**, then come back.
5. "There may be more than one problem" → after the first fix, **check again** (`break.sh 5`, `10`).
6. Fix the **root cause**, not the symptom: deleting a stuck pod isn't fixing the scheduler.
7. **Persist** fixes: `systemctl enable`, sysctl in `/etc/sysctl.d/`, manifests on disk (not `k edit` of a mirror pod, which does nothing).
8. Verify, then `exit` the ssh session.

---

## 9. Self-check: "what would you do?"

1. New pods Pending, `k describe` shows **no events at all**.
2. `k create deploy x --image=nginx` succeeds, `k get rs` shows nothing.
3. `The connection to the server 172.30.1.2:6443 was refused`.
4. Pod `CrashLoopBackOff`, `k logs` is empty.
5. Pod Last State `OOMKilled`, exit 137.
6. Node `NotReady`, `systemctl status kubelet` = active (running).
7. `k top pods` → `Metrics API not available`.
8. You edited `kube-apiserver.yaml`, 5 minutes later there's still no API server container in `crictl ps -a`.
9. Deployment stuck at 2/3, the third pod is Pending with `0/3 nodes are available: 1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: }, 2 Insufficient memory`.
10. You fixed kubelet on node01 with `systemctl start kubelet`. Is the task fully done?

> [!success]- Answers
> 1. Scheduler is down (check kube-system pods/logs, its manifest), or `schedulerName` points to a scheduler that doesn't exist.
> 2. Controller-manager down → its manifest/logs.
> 3. API server down (ssh cp → `crictl ps -a` → `crictl logs`) or kubeconfig points to the wrong IP/port.
> 4. `k logs -p` (the previous container), `k describe` (exit code, command), check `command`/`args`.
> 5. Raise the memory limit (or fix the leak). Check `k top` for real usage.
> 6. `journalctl -u kubelet`: probably it runs but can't register (wrong server/port, certs), or the CNI/containerd is broken (`describe node` conditions/messages).
> 7. metrics-server isn't running/healthy → `k -n kube-system get deploy metrics-server`, its logs.
> 8. The manifest probably has a YAML error → `journalctl -u kubelet | grep -i manifest`, or a missing file in a hostPath. Compare with your backup.
> 9. The workers lack memory for the request → lower the request (or free resources). Don't remove the control-plane taint unless asked.
> 10. No. `systemctl enable kubelet` too, so it survives a reboot.

---

## 10. Practice plan with your lab

```bash
./troubleshoot/break.sh list
# Round 1: untimed, use this note. Round 2: timed <5 min, no notes. Round 3: <4 min.
# After each: ./troubleshoot/check.sh <n>
# Map: 1 scheduler (§4) · 2 kubelet stopped (§5) · 3 kubelet config (§5) · 4 apiserver/etcd (§4)
#      5 service (§3) · 6 DNS (§3) · 7 NetworkPolicy (§3) · 8 controller-manager (§1, §4) · 9 PVC (05-storage §8) · 10 app (§1)
# Make your own: break something in a static manifest, swap two people's roles, and fix it from the logs only.
```

---
← [[07-cluster-maintenance]] · [[00 Home|🏠 Home]] · [[09-scheduling-placement]] →
