# Core objects: Pod, ReplicaSet, Deployment, DaemonSet, StatefulSet, Job, CronJob, Service

How to read this: go top to bottom once. Every section has **an annotated YAML**, **why it exists**, **how it works inside**, and **commands**.
The side-by-side comparisons are in section 10. Self-check questions are at the end.

---

## 0. What happens when you run `kubectl apply -f x.yaml`

```
 you ── kubectl apply ──▶ kube-apiserver ──▶ etcd (stores the object: "desired state")
                               │
                               ├─▶ controller-manager  (Deployment controller → creates ReplicaSet,
                               │                         ReplicaSet controller → creates Pod objects)
                               │
                               ├─▶ kube-scheduler      (sees Pod with no node → picks a node,
                               │                         writes spec.nodeName)
                               │
                               └─▶ kubelet on that node (sees a Pod assigned to it → asks
                                                          containerd to pull image + start containers,
                                                          reports status back)
 kube-proxy on every node: watches Services/EndpointSlices → writes iptables/nftables rules
```

Key ideas:
- **Nothing talks to etcd except the API server.** Everyone else watches the API server.
- **Controllers run loops:** *desired (spec) ≠ actual (status)? → act.* This is why a deleted pod comes back.
- **The scheduler only picks a node.** The kubelet actually runs the pod.
- When troubleshooting, ask **which step in this chain broke**:
  - Pod `Pending` → scheduler problem (resources, taints, nodeSelector, PVC)
  - `ContainerCreating` / `ImagePullBackOff` → kubelet/runtime/image problem
  - `CrashLoopBackOff` → your app/command problem

---

## 1. Anatomy of every object

```yaml
apiVersion: apps/v1        # API group + version. Core objects (Pod, Service, ConfigMap...) are just "v1"
kind: Deployment           # the TYPE of object
metadata:                  # identity
  name: web                #   unique per kind per namespace
  namespace: prod          #   omitted → "default" (or whatever your context says)
  labels:                  #   key/value tags used by SELECTORS (to find things)
    app: web
  annotations:             #   key/value notes NOT used for selecting (tools, humans, change-cause)
    kubernetes.io/change-cause: "bump to 1.28"
spec:                      # DESIRED state: you write this. Shape depends on kind
  ...
status:                    # ACTUAL state: Kubernetes writes this. Never put it in your YAML
  ...
```

| kind | apiVersion | short name | namespaced? |
|---|---|---|---|
| Pod | v1 | po | yes |
| Service | v1 | svc | yes |
| ConfigMap / Secret | v1 | cm / — | yes |
| Namespace | v1 | ns | **no** |
| Node / PersistentVolume | v1 | no / pv | **no** |
| ReplicaSet | apps/v1 | rs | yes |
| Deployment | apps/v1 | deploy | yes |
| DaemonSet | apps/v1 | ds | yes |
| StatefulSet | apps/v1 | sts | yes |
| Job | batch/v1 | — | yes |
| CronJob | batch/v1 | cj | yes |

You don't need to memorize this table:
```bash
k api-resources                       # every kind, apiVersion, shortname, namespaced
k explain deploy.spec.strategy        # field docs, offline, fast, works in the exam
k explain pod.spec --recursive | less # the whole field tree
```

---

## 2. Pod: the smallest thing that runs

**What:** one or more containers that are **always scheduled together on the same node**, share **one IP** (they talk over `localhost`), and can share volumes.

**Why it exists:** sometimes containers must live together, for example an app plus a log-shipper sidecar. The pod is the "box" around them.

**Its weakness:** a bare pod is **not self-healing**. If it's deleted or its node dies, nothing recreates it. That's why controllers (Deployment etc.) exist.

### Fully annotated Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web-pod
  labels:
    app: web            # labels are free-form; YOU choose the keys
    tier: frontend      # "tier" has no meaning to Kubernetes. It's just a convention
spec:
  restartPolicy: Always # Always (default) | OnFailure | Never. Applies to ALL containers in the pod
  nodeSelector:         # schedule only onto nodes with this label (k get nodes --show-labels)
    disktype: ssd
  tolerations:          # allow scheduling onto nodes with a matching taint
  - key: "env"
    operator: "Equal"
    value: "prod"
    effect: "NoSchedule"
  serviceAccountName: web-sa   # identity the pod uses to call the API (RBAC). Default: "default"

  initContainers:       # run ONE BY ONE, each must finish successfully BEFORE main containers start
  - name: wait-db
    image: busybox:1.36
    command: ["sh", "-c", "until nslookup db; do sleep 2; done"]
  - name: log-shipper   # NATIVE SIDECAR: an init container with restartPolicy: Always
    image: busybox:1.36 #   starts before the app, keeps running alongside it
    restartPolicy: Always
    command: ["sh", "-c", "tail -F /var/log/app/app.log"]
    volumeMounts:
    - name: logs
      mountPath: /var/log/app

  containers:
  - name: nginx
    image: nginx:1.27          # no tag or :latest → imagePullPolicy defaults to Always, else IfNotPresent
    imagePullPolicy: IfNotPresent
    command: ["nginx"]         # overrides the image's ENTRYPOINT
    args: ["-g", "daemon off;"]# overrides the image's CMD
    ports:
    - containerPort: 80        # INFORMATIONAL ONLY: the app listens on 80 whether you write this or not
      name: http               #   ...but naming it lets a Service use targetPort: http
    env:
    - name: MODE
      value: "production"
    - name: DB_PASS
      valueFrom:
        secretKeyRef: {name: db-secret, key: password}
    envFrom:
    - configMapRef: {name: web-config}   # every key in the ConfigMap becomes an env var
    resources:
      requests:                # the SCHEDULER uses requests: "find a node with this much free"
        cpu: 100m              #   1 CPU = 1000m. 100m = 0.1 core
        memory: 128Mi          #   Mi = mebibytes (use Mi/Gi, not M/G by habit)
      limits:                  # the KUBELET/kernel enforces limits at runtime
        cpu: 500m              #   over CPU limit → THROTTLED (slowed down, not killed)
        memory: 256Mi          #   over memory limit → OOMKilled (exit code 137), then restarted
    readinessProbe:            # "ready for traffic?" fail → removed from Service endpoints (NOT restarted)
      httpGet: {path: /, port: 80}
      initialDelaySeconds: 5
      periodSeconds: 5
    livenessProbe:             # "still alive?"  fail → container is KILLED and RESTARTED
      tcpSocket: {port: 80}
      periodSeconds: 10
      failureThreshold: 3
    startupProbe:              # "finished booting?" other probes are disabled until this succeeds
      httpGet: {path: /, port: 80}
      failureThreshold: 30
      periodSeconds: 2
    volumeMounts:
    - name: logs
      mountPath: /var/log/app

  volumes:                     # declared at POD level, mounted per container
  - name: logs
    emptyDir: {}               # empty dir, lives as long as the pod, shared by its containers
```

### Pod lifecycle

| Pod `phase` | Meaning |
|---|---|
| Pending | Accepted, but not running yet: not scheduled, or images still pulling |
| Running | Bound to a node, at least one container running |
| Succeeded | All containers exited 0 and won't restart (Jobs) |
| Failed | All containers terminated, at least one failed |
| Unknown | Node not reporting (node down / kubelet dead) |

The STATUS column in `k get po` shows more detail than the phase:

| STATUS | Usual cause | Look at |
|---|---|---|
| Pending | no node fits: resources, taint, nodeSelector, unbound PVC | `k describe po` → Events |
| ContainerCreating | volume/secret/configmap missing, CNI problem | `k describe po` |
| ErrImagePull / ImagePullBackOff | wrong image name/tag, private registry | `k describe po` |
| CrashLoopBackOff | container starts then exits again and again | `k logs po --previous` |
| OOMKilled | exceeded memory limit | `k describe po` → Last State |
| Running but 0/1 READY | readiness probe failing | `k describe po` → Events |
| CreateContainerConfigError | referenced configMap/secret **key** missing | `k describe po` |

### QoS classes (decide who is evicted first when a node runs out of memory)

| QoS | Rule | Evicted |
|---|---|---|
| **Guaranteed** | every container has cpu+memory limits, and requests == limits | last |
| **Burstable** | at least one request/limit set, but not Guaranteed | middle |
| **BestEffort** | no requests/limits at all | **first** |

`k get po web-pod -o jsonpath='{.status.qosClass}'`

---

## 3. Labels, selectors, annotations: how objects find each other

**Objects are linked by LABELS, not by names.** This is the most important idea in Kubernetes.

```
Deployment.spec.selector  ──┐
Service.spec.selector     ──┼──▶ match Pod.metadata.labels
NetworkPolicy.podSelector ──┘
```

Two selector syntaxes:

```yaml
# Equality-based (Service only supports this simple map form)
selector:
  app: web
  tier: frontend          # AND: pod must have BOTH labels

# Set-based (Deployment / ReplicaSet / Job / NetworkPolicy etc.)
selector:
  matchLabels:
    app: web
  matchExpressions:
  - {key: tier, operator: In, values: [frontend, edge]}   # In | NotIn | Exists | DoesNotExist
```

Commands:
```bash
k get po --show-labels
k get po -l app=web,tier=frontend          # AND
k get po -l 'tier in (frontend,backend)'   # set-based
k get po -l 'env!=prod'
k get po -L tier                           # show the "tier" label as a column
k label po web-pod env=prod                # add
k label po web-pod env=dev --overwrite     # change
k label po web-pod env-                    # remove
k label node w1 disktype=ssd               # nodes have labels too (used by nodeSelector)
```

**Label vs annotation:**

| | Label | Annotation |
|---|---|---|
| Used for selecting? | **yes** | no |
| Value size | short (≤ 63 chars) | can be large |
| Typical use | app, tier, env, version | change-cause, ingress config, tool metadata |

---

## 4. ReplicaSet: keeps N identical pods alive

**Why:** self-healing and scaling. "There must always be 3 pods matching `app=web`."

**How it works:** it counts the pods that match its selector, then creates or deletes pods (from `template`) until the count equals `replicas`.

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: web-rs
spec:
  replicas: 3                # desired count
  selector:                  # "which pods are mine?"
    matchLabels:
      app: web
  template:                  # blueprint for NEW pods (exactly a Pod's metadata+spec)
    metadata:
      labels:
        app: web             # MUST satisfy the selector, or the API rejects it
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
```

Important behaviors:
- **It only counts by label.** If you remove `app=web` from one of its pods, the RS no longer owns that pod, so it creates a new one. The old pod keeps running as an orphan.
- **It adopts orphans.** A bare pod you create with `app=web` gets adopted. If that makes 4 pods, the RS deletes one.
- **Changing `template` does NOT touch existing pods.** If you change the image in an RS, the old pods keep the old image. Only new pods get the new one. **This is exactly why Deployments exist.**
- Ownership is visible in `k get po <name> -o yaml` → `metadata.ownerReferences`.

**In practice you never create ReplicaSets yourself. Deployments create them.**

---

## 5. Deployment: ReplicaSets + versioned rolling updates

**Why:** you want to change the image or config **with no downtime** and be able to **roll back**.

**How:** each time the **pod template** changes, the Deployment creates a **new ReplicaSet** and gradually scales **new up / old down**. Old ReplicaSets are kept at 0 replicas as rollback history.

```
Deployment web
 ├── ReplicaSet web-7c9f8d6b5d (nginx:1.27)  replicas 3 → 2 → 1 → 0   (kept for rollback)
 └── ReplicaSet web-5b8d4f7c9a (nginx:1.28)  replicas 0 → 1 → 2 → 3
          └── Pod web-5b8d4f7c9a-x7k2p    ← name = <deploy>-<pod-template-hash>-<random>
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels:
    app: web                  # label of the Deployment ITSELF (just for you; not used for selecting pods)
spec:
  replicas: 3
  revisionHistoryLimit: 10    # how many old ReplicaSets to keep for rollback (default 10)
  selector:                   # IMMUTABLE after creation. To change it, delete and recreate
    matchLabels:
      app: web
  strategy:
    type: RollingUpdate       # default. Alternative: Recreate (kill all old, THEN start new → downtime)
    rollingUpdate:
      maxSurge: 25%           # how many EXTRA pods above replicas during an update (default 25%)
      maxUnavailable: 25%     # how many may be missing below replicas during an update (default 25%)
  minReadySeconds: 0          # a new pod counts as available only after being Ready this long
  template:                   # ← changing ANYTHING here = a new revision = rollout
    metadata:
      labels:
        app: web
        tier: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        resources:
          requests: {cpu: 100m, memory: 128Mi}
          limits:   {memory: 256Mi}
```

What triggers a rollout and what doesn't:
- **Triggers:** anything under `spec.template` (image, env, resources, labels in template...).
- **Does NOT trigger:** changing `replicas`. That only scales the current ReplicaSet.

Commands:
```bash
k create deploy web --image=nginx:1.27 --replicas=3 --port=80 $do > web.yaml
k scale deploy web --replicas=5
k set image deploy/web nginx=nginx:1.28              # nginx = the CONTAINER NAME
k set resources deploy web -c nginx --limits=memory=256Mi
k rollout status deploy/web
k rollout history deploy/web
k rollout history deploy/web --revision=2            # what was in revision 2
k rollout undo deploy/web                            # back to the previous revision
k rollout undo deploy/web --to-revision=1
k rollout restart deploy/web                         # recreate all pods (same spec)
k rollout pause deploy/web / resume                  # batch several edits into one rollout
k annotate deploy web kubernetes.io/change-cause="bump to 1.28"   # shows in history
```

---

## 6. The other workload controllers

### DaemonSet: one pod on every (matching) node
**Why:** node-level agents such as log collectors, monitoring exporters, CNI (calico-node), and kube-proxy.
- It has **no `replicas` field**. The count = the number of eligible nodes.
- When a new node joins, the pod is added automatically.
- Control-plane nodes have the taint `node-role.kubernetes.io/control-plane:NoSchedule`. To run there too, add a toleration.

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
spec:
  selector:
    matchLabels: {app: node-agent}
  template:
    metadata:
      labels: {app: node-agent}
    spec:
      tolerations:                         # also run on the control-plane node
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: agent
        image: busybox:1.36
        command: ["sh", "-c", "while true; do date; sleep 30; done"]
```
**No `k create ds` command exists. Exam trick:** generate a deployment YAML, change `kind: DaemonSet`, and delete `replicas`, `strategy` and `status`.

### StatefulSet: pods with a stable identity
**Why:** databases and clustered apps that need **stable names**, **stable per-pod storage**, and **ordered startup**.

| Deployment pod | StatefulSet pod |
|---|---|
| `web-5b8d4f7c9a-x7k2p` (random, new on every restart) | `db-0`, `db-1`, `db-2` (fixed, reused) |
| all pods share one PVC (or none) | **each pod gets its own PVC** via volumeClaimTemplates |
| started/stopped in parallel | started 0→1→2, stopped 2→1→0 (default) |
| reached via the Service IP | each pod has its own DNS: `db-0.db.<ns>.svc.cluster.local` |

```yaml
apiVersion: v1
kind: Service
metadata:
  name: db
spec:
  clusterIP: None             # HEADLESS Service: gives each pod a DNS name, no load-balanced IP
  selector: {app: db}
  ports:
  - port: 5432
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
spec:
  serviceName: db             # the headless Service above
  replicas: 3
  selector:
    matchLabels: {app: db}
  template:
    metadata:
      labels: {app: db}
    spec:
      containers:
      - name: pg
        image: postgres:17
        env: [{name: POSTGRES_PASSWORD, value: pass}]
        volumeMounts:
        - {name: data, mountPath: /var/lib/postgresql/data}
  volumeClaimTemplates:       # creates PVCs data-db-0, data-db-1, data-db-2
  - metadata:
      name: data
    spec:
      accessModes: [ReadWriteOnce]
      resources:
        requests: {storage: 1Gi}
```

### Job: run to completion
**Why:** one-off tasks such as migrations, backups, and batch processing. **Success = the pod exits 0.**

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pi
spec:
  completions: 5               # need 5 successful pods in total (default 1)
  parallelism: 2               # run up to 2 at a time (default 1)
  backoffLimit: 4              # retries before the Job is marked Failed (default 6)
  activeDeadlineSeconds: 120   # kill the whole Job after 120s
  ttlSecondsAfterFinished: 600 # auto-delete the Job 10 min after it finishes
  template:
    spec:
      restartPolicy: Never     # MUST be Never or OnFailure (Always is not allowed for Jobs)
      containers:
      - name: pi
        image: perl:5.40
        command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(200)"]
```

### CronJob: a Job on a schedule
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup
spec:
  schedule: "*/5 * * * *"          # min hour day-of-month month day-of-week → every 5 min
  concurrencyPolicy: Forbid        # Allow (default) | Forbid (skip if the previous run is still running) | Replace
  successfulJobsHistoryLimit: 3    # default 3
  failedJobsHistoryLimit: 1        # default 1
  startingDeadlineSeconds: 60
  jobTemplate:                     # ← a full Job spec goes here
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: busybox:1.36
            command: ["sh", "-c", "date; echo backing up"]
```
Nesting to remember: **CronJob → jobTemplate → (Job) spec → template → (Pod) spec → containers**

```bash
k create job pi --image=perl:5.40 $do -- perl -Mbignum=bpi -wle 'print bpi(200)'
k create cronjob backup --image=busybox:1.36 --schedule="*/5 * * * *" $do -- sh -c 'date'
k create job manual-run --from=cronjob/backup     # trigger a CronJob right now
```

---

## 7. Service: a stable address for a changing set of pods

**The problem:** pods die and come back with **new IPs**, and there are several of them. Clients need **one fixed name/IP** plus load balancing.

**How it works:**
1. You create a Service with a `selector`.
2. The EndpointSlice controller continuously lists **Ready** pods matching the selector and writes their IP:port into **EndpointSlices**.
3. **kube-proxy** on every node turns that into iptables/nftables rules: "traffic to ClusterIP:port → pick one pod IP:targetPort".
4. **CoreDNS** gives the Service a name: `<svc>.<ns>.svc.cluster.local` → ClusterIP.

The ClusterIP is **virtual**. No interface owns it, so **you can't ping it**. Test with `curl`/`wget` on the port.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-svc
  namespace: default
spec:
  type: NodePort              # ClusterIP (default) | NodePort | LoadBalancer | ExternalName
  selector:                   # pods with app=web AND tier=frontend (simple map, AND)
    app: web
    tier: frontend
  ports:
  - name: http                # REQUIRED when there is more than one port
    protocol: TCP
    port: 80                  # the port on the SERVICE (clients call web-svc:80)
    targetPort: 8080          # the port on the POD/container (number, or a named containerPort like "http")
    nodePort: 30080           # only for NodePort/LoadBalancer: port on EVERY node (30000-32767). Omit → random
```

### The three ports (people mix these up all the time)

```
client ──▶ <NodeIP>:30080 ──▶ web-svc (ClusterIP):80 ──▶ pod IP:8080
            nodePort              port                    targetPort  (= containerPort)
```

### Service types side by side

| Type | Gets a ClusterIP? | Reachable from | Use case |
|---|---|---|---|
| **ClusterIP** (default) | yes | inside the cluster only | internal backends (db, api) |
| **NodePort** | yes | outside, via `anyNodeIP:30000-32767` | quick external access, labs |
| **LoadBalancer** | yes + nodePort | outside, via a cloud LB IP | production on a cloud |
| **ExternalName** | no | — (DNS CNAME to `externalName: db.example.com`) | alias for an external host |
| **Headless** (`clusterIP: None`) | **no** | DNS returns **pod IPs directly** | StatefulSets, client-side discovery |

Each type builds on the previous one: LoadBalancer ⊃ NodePort ⊃ ClusterIP.

**A Service without a selector** gets no automatic endpoints. You create the EndpointSlice yourself, for example to point at an external IP.

Commands:
```bash
k expose deploy web --name=web-svc --port=80 --target-port=8080 --type=NodePort $do
#   ↑ copies the deployment's selector. Usually what you want
k create svc clusterip web-svc --tcp=80:8080 $do
#   ↑ WARNING: sets selector app=web-svc (the svc name!). You usually have to fix the selector
k run tmp --image=busybox:1.36 --rm -it --restart=Never -- wget -qO- -T2 web-svc:80
k get svc,endpointslices -l kubernetes.io/service-name=web-svc
k get endpoints web-svc        # older API, still works (prints a deprecation warning)
```

### Service not working? Debug in this order
1. `k get endpoints web-svc`: **empty?** → the selector doesn't match the pod labels, **or** the pods aren't Ready (readiness probe).
   Compare `k describe svc web-svc | grep Selector` with `k get po --show-labels`.
2. Endpoints exist, but you get "connection refused"? → **targetPort is wrong** (the app listens on a different port). Check `k exec po -- netstat -tlnp`, or the image docs.
3. Works by IP but not by name? → DNS. Check that the name and namespace are right (`svc.ns`), and that CoreDNS is running.
4. Works inside the namespace but not from another one? → a NetworkPolicy, or you used the short name from another namespace.

---

## 8. How it all fits together

```
                     (outside world)
                           │
                Ingress / Gateway API (HTTP routing by host/path)
                           │
                    Service web-svc  ── selector app=web ──┐
                    (stable IP + DNS)                      │
                                                           ▼
 Deployment web ──owns──▶ ReplicaSet web-5b8d.. ──owns──▶ Pod  Pod  Pod  (labels app=web)
   (versions,               (keeps N alive)                │
    rollouts)                                              └─ uses ConfigMap, Secret, PVC, ServiceAccount
```

- The **Deployment** decides *what* runs and *how to update it*.
- The **ReplicaSet** keeps *how many* running.
- The **Pod** is *the actual running containers*.
- The **Service** decides *how to reach them*.
- **Labels** are the glue between all of them.

---

## 9. Imperative generators (the exam speed toolkit)

```bash
export do="--dry-run=client -o yaml"    # already in your cka.bashrc
export now="--force --grace-period=0"

k run nginx --image=nginx:1.27 --labels=app=web,tier=frontend --port=80 $do
k run nginx --image=nginx:1.27 --port=80 --expose          # pod + ClusterIP svc in one step
k run tmp --image=busybox:1.36 --rm -it --restart=Never -- sh   # throwaway debug pod
k create deploy web --image=nginx:1.27 --replicas=3 $do
k create job j1 --image=busybox:1.36 $do -- sh -c 'echo hi'
k create cronjob c1 --image=busybox:1.36 --schedule="0 * * * *" $do -- date
k expose deploy web --port=80 --target-port=8080 --type=NodePort $do
k create cm web-config --from-literal=MODE=prod $do
k create secret generic db-secret --from-literal=password=s3cret $do
k delete po nginx $now                                     # delete fast
k get po nginx -o yaml > p.yaml   # edit, then: k replace -f p.yaml --force
```

No imperative command: **DaemonSet** (convert a deployment), **StatefulSet**, **PV/PVC** (copy from the docs), **NetworkPolicy** (copy from the docs).

---

## 10. Side-by-side comparisons

### Workload controllers

| | Pod | ReplicaSet | Deployment | DaemonSet | StatefulSet | Job | CronJob |
|---|---|---|---|---|---|---|---|
| apiVersion | v1 | apps/v1 | apps/v1 | apps/v1 | apps/v1 | batch/v1 | batch/v1 |
| Self-healing | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ (retries until backoffLimit) | ✅ (via Jobs) |
| How many pods | 1 | `replicas` | `replicas` | 1 per node | `replicas` | `completions` | per run |
| Rolling update + rollback | ❌ | ❌ | ✅ | ✅ (rolling; `rollout undo` works) | ✅ (ordered) | ❌ | ❌ |
| Pod names | yours | `rs-xxxxx` | `deploy-hash-xxxxx` | `ds-xxxxx` | `sts-0`, `sts-1` | `job-xxxxx` | `cj-<time>-xxxxx` |
| Own storage per pod | ❌ | ❌ | ❌ | ❌ | ✅ volumeClaimTemplates | ❌ | ❌ |
| Runs forever? | yes | yes | yes | yes | yes | **no, until success** | **no, on a schedule** |
| restartPolicy | any | Always | Always | Always | Always | **Never / OnFailure** | **Never / OnFailure** |
| Imperative create | `k run` | ❌ | `k create deploy` | ❌ | ❌ | `k create job` | `k create cronjob` |
| Typical use | debugging | (made by Deployment) | stateless apps | node agents | databases | migration, backup | scheduled backup |

### Pod vs ReplicaSet vs Deployment (the classic exam question)

| Question | Pod | ReplicaSet | Deployment |
|---|---|---|---|
| Deleted pod comes back? | no | yes | yes |
| Can scale? | no | yes | yes |
| Change the image → existing pods updated? | (can't edit most pod fields) | **no**, only new pods | **yes**, rolling update |
| Rollback? | no | no | **yes** |
| Who creates it in practice? | you (debug), controllers | the Deployment | you |

### Probes

| | readinessProbe | livenessProbe | startupProbe |
|---|---|---|---|
| Question it asks | ready for traffic? | still healthy? | done starting? |
| On failure | removed from Service endpoints | **container restarted** | container restarted (after failureThreshold) |
| Typical mistake | wrong port → pod never Ready → empty endpoints | too aggressive → restart loop | — |

### requests vs limits

| | requests | limits |
|---|---|---|
| Used by | scheduler (placement) | kubelet / kernel (enforcement) |
| CPU exceeded | — | throttled |
| Memory exceeded | — | OOMKilled (137) |
| Too high | pod stays **Pending** (no node fits) | — |

---

## 11. Self-check (answer without looking, then verify on the cluster)

1. You remove the label `app=web` from one pod of a 3-replica Deployment. What happens to that pod, and how many pods carry `app=web` afterwards?
2. You `k edit rs web-xxxx` and change the image. Do the running pods change? Why does a Deployment behave differently?
3. A Service has endpoints, but `curl` gives "connection refused". What's the most likely wrong field?
4. A Service has **no** endpoints, and the labels match. What else can cause this?
5. You need a pod on every node, including the control plane. Which kind, and what extra field?
6. Which `restartPolicy` values are allowed for a Job, and why not `Always`?
7. A pod has `limits: memory: 256Mi` and no requests. What is its memory request, and what is its QoS class if it also has a CPU limit?
8. What is the DNS name of pod `db-1` in StatefulSet `db` (headless svc `db`) in namespace `data`?
9. Which change triggers a new rollout: `replicas: 5`, or adding an env var?
10. `k create svc nodeport api --tcp=80:8080`: what selector does it get, and why is that a trap?

<details><summary>Answers</summary>

1. The pod loses its owner (orphaned) and keeps running. The RS sees only 2 matching pods and creates a new one, so 3 pods have `app=web` plus 1 orphan. The Service also stops sending traffic to the orphan.
2. No. An RS uses its template only when creating new pods. A Deployment creates a **new RS** and rolls pods over to it.
3. `targetPort` doesn't match the port the container actually listens on.
4. The pods are not Ready (readiness probe failing), or the Service is in a different namespace than the pods. (A selector with an extra label the pods don't have is effectively a mismatch too.)
5. A DaemonSet, plus a toleration for `node-role.kubernetes.io/control-plane:NoSchedule`.
6. `Never` or `OnFailure`. A Job must be able to finish, and `Always` would restart the container even after success.
7. Requests default to the limits, so 256Mi. With a CPU limit too, requests = limits for both → **Guaranteed**.
8. `db-1.db.data.svc.cluster.local`
9. Adding an env var (it's in `spec.template`). `replicas` only scales.
10. `app=api`. It's only right if your pods actually have that label. Always check `k get ep` afterwards.
</details>
