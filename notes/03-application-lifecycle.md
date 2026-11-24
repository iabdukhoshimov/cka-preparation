# 03: Application lifecycle management (deploy, configure, update, scale)

Domain: **Workloads & Scheduling (15%)**. These tasks also show up inside troubleshooting tasks, because half of the "broken app" tasks are a wrong env var, a wrong probe, or wrong resources.
Basics of Deployment/ReplicaSet/Job are in `01-core-objects.md`. This note goes **deeper on what you change during an app's life.**

Tags: 🔥 HIGH (must be fast) · 🟡 MEDIUM (know the steps) · 🧊 LOW (know the idea)

---

## The big picture in one story: a restaurant's life

| App lifecycle step | 🍽 Restaurant | 🚗 Car | 🎬 Cinema |
|---|---|---|---|
| Deployment | the restaurant chain's head office: "this branch runs 3 chefs" | the fleet manager: "keep 3 taxis on the road" | the cinema manager: "3 halls show this film" |
| Rolling update | swap chefs one at a time, so the kitchen never closes | replace taxis one at a time, so service never stops | switch halls to the new film one by one |
| Recreate strategy | close the restaurant for renovation, then reopen | park the whole fleet, then send out new cars | stop all halls, then start the new film everywhere |
| Rollback | the new menu flopped, so bring back yesterday's menu | the new tyres are bad, so put the old ones back | the new film is broken, so show the old one again |
| command / args | the recipe (what to cook) / the order details (how spicy) | the ignition / the GPS destination | the projector / which reel to play |
| ConfigMap | the menu board on the wall (anyone can read it) | the car's settings (seat position, radio presets) | the film schedule poster |
| Secret | the safe in the manager's office | the car key in your pocket | the projectionist's booth key |
| Init container | prep cooks chop vegetables *before* the kitchen opens | pre-drive checklist: fuel, mirrors, seatbelt | the cleaners clean the hall *before* the audience enters |
| Sidecar | the waiter who works next to the chef the whole shift | the co-driver reading the map the whole rally | the usher standing in the hall during the whole film |
| Probes | the manager checks: "is the chef awake? ready to take orders?" | dashboard warning lights | staff check: is the projector on? is the sound working? |
| Requests / limits | reserved tables / maximum seats you may use | your reserved parking spot / the speed limiter | your booked seats / the fire-safety maximum per hall |
| HPA | open more tables at lunch rush, close them at night | add taxis at rush hour | open extra halls for a blockbuster premiere |

---

## 0. Namespaces 🔥 HIGH (every task names one)

### Analogies
- 🏢 **Office building:** one building (the cluster), many floors (namespaces). Two floors can each have a room called "kitchen" (the same name in different namespaces). The lifts and electricity (Nodes, PVs, StorageClasses) are shared by every floor, so they're **not** on any floor (cluster-scoped).
- ⚽ **Football club:** the first team, the U21 team and the women's team are separate squads. Each can have a player named "Ali". The stadium (nodes) is shared.

| Namespace | What lives there |
|---|---|
| `default` | where your objects go if you don't say otherwise |
| `kube-system` | control plane pods, CoreDNS, kube-proxy, CNI |
| `kube-public` | readable by everyone (cluster-info ConfigMap) |
| `kube-node-lease` | **Lease** objects = node heartbeats (how the control plane knows a node is alive) |

- Namespaced: Pods, Deployments, Services, ConfigMaps, Secrets, PVCs, Roles, RoleBindings, NetworkPolicies, ServiceAccounts, Ingress, HTTPRoute...
- Cluster-scoped: Nodes, PVs, StorageClasses, Namespaces, ClusterRoles, ClusterRoleBindings, PriorityClasses, CRDs, IngressClass, GatewayClass. List them: `k api-resources --namespaced=false`.
- Every namespace automatically gets the label `kubernetes.io/metadata.name=<name>` (NetworkPolicy uses it a lot).
- **Deleting a namespace deletes EVERYTHING in it.** Be careful in the exam.

```bash
k create ns dev
k get all -n dev                 # "all" = pods, svc, deploy, rs, ds, sts, job, cj. NOT cm/secret/pvc/ingress/netpol
k get po -A                      # all namespaces
k config set-context --current --namespace=dev
k config view --minify | grep namespace
```
⚠️ **Exam trap:** switch the namespace in your context, forget about it, and the next task's objects land in the wrong place. Prefer `-n <ns>` on every command, and put `namespace:` in YAML metadata.

---

## 1. Rolling updates, strategies and rollbacks 🔥 HIGH

### Analogies
- 🍽 **Restaurant (RollingUpdate):** you're changing the menu. You don't close the restaurant. You train **one** chef on the new menu (surge), then send one old chef home (unavailable), and repeat. Customers always get served.
- 🍽 **Restaurant (Recreate):** renovation day. "Closed today." All old chefs go home first, then the new team starts. There's **downtime**, but old and new are never mixed (needed when two versions can't share one database).
- ⚽ **Football substitutions:** RollingUpdate = substitute players one at a time while the match continues. `maxSurge` = how many extra players may warm up on the touchline at once. `maxUnavailable` = how many positions may be empty during the swap.
- 🎬 **Cinema rollback:** the new 3D projector breaks. The manager says "put back the old projector we kept in storage" (the old ReplicaSet at 0 replicas is that storage).

### The math (exam asks "how many pods at most / at least during an update?")
```
replicas: 4, maxSurge: 25%, maxUnavailable: 25%
maxSurge       → 25% of 4 = 1   (percent is ROUNDED UP)
maxUnavailable → 25% of 4 = 1   (percent is ROUNDED DOWN)
→ at most 4+1 = 5 pods total, at least 4-1 = 3 available during the rollout

replicas: 10, maxSurge: 0, maxUnavailable: 2   → never more than 10 pods, kill 2 old, start 2 new...
replicas: 3,  maxSurge: 1, maxUnavailable: 0   → "zero-downtime": always 3 ready, 1 extra while updating
```
⚠️ `maxSurge` and `maxUnavailable` **cannot both be 0** (the rollout could never move).

```yaml
spec:
  replicas: 4
  strategy:
    type: RollingUpdate          # or: Recreate (then NO rollingUpdate block allowed)
    rollingUpdate:
      maxSurge: 1                # number or percent
      maxUnavailable: 0
  minReadySeconds: 10            # new pod must stay Ready 10s before it counts as "available"
  progressDeadlineSeconds: 600   # after 10 min with no progress → condition Progressing=False (ProgressDeadlineExceeded)
  revisionHistoryLimit: 10       # old ReplicaSets kept for rollback
```

### Commands you must type without thinking
```bash
k set image deploy/web nginx=nginx:1.28          # "nginx=" is the CONTAINER name, not the image
k set image deploy/web '*=nginx:1.28'            # every container
k rollout status deploy/web                      # blocks until done (or failed)
k rollout history deploy/web
k rollout history deploy/web --revision=3        # see the template of revision 3
k rollout undo deploy/web                        # to the previous revision
k rollout undo deploy/web --to-revision=2
k rollout restart deploy/web                     # new pods, same spec (e.g., after a ConfigMap change)
k rollout pause deploy/web; k set image ...; k set resources ...; k rollout resume deploy/web   # one rollout for many edits
k annotate deploy/web kubernetes.io/change-cause="image 1.28"   # shows in CHANGE-CAUSE of history
k edit deploy web --record   # ❌ --record is deprecated; use the annotation above
```

### Blue/green and canary with plain Kubernetes (no service mesh) 🟡
- **Blue/green** = two Deployments (`web-blue`, `web-green`), one Service. Switch the Service selector `version: blue → green`. 🎬 Like moving the audience from Hall 1 to Hall 2 in one announcement.
- **Canary** = two Deployments with the **same** `app=web` label (the Service selects both), e.g. 9 replicas old + 1 replica new → ~10% traffic to the new version. ⚽ Like letting a young player play 10 minutes before giving them the full match.
- With Gateway API you can do exact weights (`backendRefs` with `weight`). See `06-networking.md`.

⚠️ Traps:
- A rollout that is stuck (bad image) does **not** roll back automatically. You must `k rollout undo`.
- Rollback = going back to an older **template**. It does **not** undo `replicas` changes.
- `k rollout undo` on a Deployment whose old ReplicaSets were deleted (or `revisionHistoryLimit: 0`) has nothing to go back to.

---

## 2. Commands and arguments 🔥 HIGH

### Analogies
- 🚗 **Car:** `command` = which engine starts (the ignition). `args` = where you drive (the GPS destination). Changing the destination doesn't change the engine.
- 🍽 **Restaurant:** `command` = the dish ("pizza"). `args` = the details ("extra cheese, no olives").
- ✈️ **Airport:** `command` = the airline. `args` = the destination and seat.

### Docker ↔ Kubernetes mapping (memorize this table)

| Dockerfile | Kubernetes | Meaning |
|---|---|---|
| `ENTRYPOINT` | `command` | the program to run |
| `CMD` | `args` | default arguments to that program |

| You set in the pod | What runs |
|---|---|
| nothing | image ENTRYPOINT + image CMD |
| only `args` | image ENTRYPOINT + **your args** |
| only `command` | **your command** (image CMD is ignored!) |
| both | your command + your args |

```yaml
containers:
- name: app
  image: busybox:1.36
  command: ["sh", "-c"]                              # ENTRYPOINT
  args: ["echo Hello $(NAME); sleep 3600"]           # CMD. $(VAR) = Kubernetes expands env vars
  env:
  - name: NAME
    value: "Ikhtiyor"
```

Imperative:
```bash
k run a --image=busybox:1.36 -- sleep 3600              # "--" then words → ARGS (image entrypoint kept)
k run b --image=busybox:1.36 --command -- sleep 3600    # --command → words become COMMAND
k create deploy d --image=busybox:1.36 -- sleep 3600    # for create deploy, words after -- become COMMAND
```

⚠️ Traps:
- `command: ["sleep 3600"]` ❌ (one string = it looks for a program literally named "sleep 3600"). Use `["sleep", "3600"]`.
- Numbers must be strings in YAML arrays: `["sleep", "3600"]`, not `[sleep, 3600]` (that's an int → validation error).
- Shell features (`&&`, `>`, `$VAR`, loops) only work through `sh -c "..."`.

---

## 3. Environment variables and ConfigMaps 🔥 HIGH

### Analogies
- 🍽 **Restaurant:** the menu board on the wall. Every chef can read it. Change the board and you don't need new chefs (if they look at the board, i.e. a mounted volume). But a chef who **memorized** the menu at the start of the shift (env vars) won't notice until the next shift (pod restart).
- 🚗 **Car:** the car's settings profile (seat, mirrors, radio). Same car model, different settings per driver.
- 🎬 **Cinema:** the schedule poster. Same film (image), different showtimes per cinema (config per environment).

**Why it exists:** one image, many environments. Don't bake `DB_HOST=prod-db` into the image.

### Create
```bash
k create cm app-cfg --from-literal=MODE=prod --from-literal=LOG=debug
k create cm app-cfg --from-file=app.properties             # key = file name, value = file content
k create cm app-cfg --from-file=config=app.properties       # custom key name
k create cm app-cfg --from-env-file=app.env                 # each KEY=VALUE line → its own key
k create cm web --from-file=./config-dir/                  # every file in the dir becomes a key
k create cm nginx-conf --from-file=nginx.conf $do > cm.yaml
```
```yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: app-cfg}
data:                       # string values only (binaryData for base64 binary)
  MODE: prod
  app.properties: |         # a "file" stored as a key: multi-line value with |
    color=blue
    timeout=30
immutable: false            # true = can never be changed. Delete and recreate to change it
```
Limit: **1 MiB** per ConfigMap (same for Secrets).

### 4 ways to use it in a pod
```yaml
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "env; ls /etc/config; sleep 3600"]
    env:
    - name: PLAIN                         # 1) a plain value
      value: "hello"
    - name: APP_MODE                      # 2) ONE key from a ConfigMap (rename allowed)
      valueFrom:
        configMapKeyRef:
          name: app-cfg
          key: MODE
          optional: false                 # default false → pod can't start if the key is missing
    - name: MY_POD_IP                     # bonus: Downward API (pod info as env)
      valueFrom:
        fieldRef: {fieldPath: status.podIP}
    envFrom:                              # 3) ALL keys as env vars
    - configMapRef:
        name: app-cfg
      prefix: CFG_                        # optional → CFG_MODE, CFG_LOG
    volumeMounts:
    - name: config                        # 4) as FILES (one file per key)
      mountPath: /etc/config
    - name: nginx
      mountPath: /etc/nginx/nginx.conf    # one file only, without hiding the rest of /etc/nginx
      subPath: nginx.conf
  volumes:
  - name: config
    configMap:
      name: app-cfg
      items:                              # optional: only some keys, custom file names
      - key: MODE
        path: mode.txt
  - name: nginx
    configMap:
      name: nginx-conf
```

### What happens when the ConfigMap changes? (exam favourite)

| Used as | Updated in the running pod? |
|---|---|
| env / envFrom | ❌ never. Restart needed: `k rollout restart deploy/x` |
| volume mount | ✅ eventually (kubelet sync, ~1 min) |
| volume mount with `subPath` | ❌ never |
| `immutable: true` ConfigMap | can't be changed at all. Delete and recreate it |

⚽ Env vars are the tactics the coach told you **in the dressing room**: changing the whiteboard afterwards doesn't reach you on the pitch. A volume mount is the **live screen on the touchline**: it updates, but the app still has to look at it (re-read the file).

### 🔥 Exam pattern: "update ConfigMap X so nginx only allows TLSv1.3, and make sure the deployment uses it"
```bash
k -n <ns> edit cm nginx-config           # change the value. "immutable"? → get -o yaml, edit, k replace --force -f
k -n <ns> rollout restart deploy nginx   # so the pods load the new config
# verify: curl --tls-max 1.2 -k https://... should FAIL, TLS 1.3 should work
```

| Symptom | Cause |
|---|---|
| `CreateContainerConfigError` | **env** refers to a ConfigMap/Secret **or key** that doesn't exist |
| `ContainerCreating` + event `FailedMount ... configmap "x" not found` | a **volume** refers to a missing ConfigMap |
| Fix | create the object/key (the pod recovers by itself), or set `optional: true` |

⚠️ Traps:
- `CreateContainerConfigError` = the ConfigMap/Secret or a **key** doesn't exist (`k describe po` says which). This is `break.sh 10`.
- A mount on `/etc/nginx` **hides everything** that was in that folder in the image. Use `subPath` for one file.
- Env var names can't contain `-` or `.`. With `envFrom`, invalid keys are skipped (an event warns you).
- ConfigMap and pod must be in the **same namespace**.

---

## 4. Secrets 🔥 HIGH

### Analogies
- 🏨 **Hotel safe:** same as a cupboard (ConfigMap), but with a lock. But in Kubernetes the "lock" is just **base64**, which is like writing the code in mirror writing. Anyone who can read the Secret can decode it. Real protection = RBAC + encryption at rest (see `04-security.md`).
- 🚗 **Car key:** you don't print the key code on the car door (image). You hand the key to the driver at the start (mount at runtime).
- ✈️ **Airport:** your passport is in your bag, not printed on your T-shirt.

### Types
| Type | Created with | Used for |
|---|---|---|
| `Opaque` | `k create secret generic` | passwords, API keys |
| `kubernetes.io/tls` | `k create secret tls x --cert=c.crt --key=c.key` | Ingress/Gateway TLS |
| `kubernetes.io/dockerconfigjson` | `k create secret docker-registry` | private image pulls |
| `kubernetes.io/service-account-token` | YAML + annotation | long-lived SA token (legacy) |
| `kubernetes.io/basic-auth`, `ssh-auth` | YAML | conventions with required keys |

A `tls` secret always has the keys `tls.crt` and `tls.key`.

```bash
k create secret generic db --from-literal=user=admin --from-literal=password='p@ss!' $do
k get secret db -o jsonpath='{.data.password}' | base64 -d; echo      # decode
echo -n 'p@ss!' | base64                       # encode for YAML. -n = no trailing newline (common bug!)
k create secret generic db --from-file=password=./pass.txt
k get secret db -o jsonpath='{.data.password}' | base64 -d > /opt/pass.txt   # exam: "write the decoded value to a file"
k create secret tls web-tls --cert=tls.crt --key=tls.key
```
```yaml
apiVersion: v1
kind: Secret
metadata: {name: db}
type: Opaque
data:                     # base64 values
  password: cEBzcyE=
stringData:               # OR plain text, the API server encodes it for you (easier in the exam)
  user: admin
```
Use it exactly like a ConfigMap: `secretKeyRef`, `secretRef` (in envFrom), and a `secret:` volume with `secretName:` (⚠️ volume uses **secretName**, ConfigMap volume uses **name**).

```yaml
volumes:
- name: creds
  secret:
    secretName: db
    defaultMode: 0400      # file permissions
```

⚠️ Traps:
- `echo 'x' | base64` without `-n` adds `\n` to the password → "wrong password" bugs.
- Secret volumes are tmpfs (RAM), never written to the node disk.
- Exam tasks often say "store the decoded value in /opt/answer.txt". Decode, then `cat` the file to check.

| | ConfigMap | Secret |
|---|---|---|
| For | non-sensitive config | passwords, keys, certs |
| Stored as | plain text | base64 (+ optional encryption at rest, `04-security.md` §9) |
| On the node | regular files | tmpfs (RAM) |
| Volume field | `configMap.name` | `secret.secretName` |
| Env field | `configMapKeyRef` / `configMapRef` | `secretKeyRef` / `secretRef` |
| Change visible in a running pod? | env ❌ · volume ✅ · subPath ❌ | same |

### Downward API: the pod learns about itself 🟡 MEDIUM
⚽ The player looks at their own shirt to see their number and team. 🎬 Your ticket tells you your hall and seat.
```yaml
apiVersion: v1
kind: Pod
metadata: {name: whoami, labels: {app: demo}}
spec:
  containers:
  - name: c
    image: busybox:1.36
    command: ["sh", "-c", "env | grep MY_; cat /etc/podinfo/labels; sleep 3600"]
    resources:
      limits: {memory: 64Mi}
    env:
    - name: MY_POD_NAME
      valueFrom: {fieldRef: {fieldPath: metadata.name}}
    - name: MY_NAMESPACE
      valueFrom: {fieldRef: {fieldPath: metadata.namespace}}
    - name: MY_POD_IP
      valueFrom: {fieldRef: {fieldPath: status.podIP}}
    - name: MY_NODE
      valueFrom: {fieldRef: {fieldPath: spec.nodeName}}
    - name: MY_SA
      valueFrom: {fieldRef: {fieldPath: spec.serviceAccountName}}
    - name: MY_MEM_LIMIT
      valueFrom: {resourceFieldRef: {containerName: c, resource: limits.memory}}
    volumeMounts:
    - {name: podinfo, mountPath: /etc/podinfo}
  volumes:
  - name: podinfo
    downwardAPI:                 # labels/annotations only as FILES (they can change)
      items:
      - path: labels
        fieldRef: {fieldPath: metadata.labels}
```
Docs search: "**Expose Pod Information to Containers Through Environment Variables**".

**Projected volume** = several sources in one directory:
```yaml
volumes:
- name: all-in-one
  projected:
    sources:
    - configMap: {name: app-cfg}
    - secret: {name: db}
    - downwardAPI: {items: [{path: labels, fieldRef: {fieldPath: metadata.labels}}]}
    - serviceAccountToken: {path: token, expirationSeconds: 3600, audience: vault}
```

---

## 5. Multi-container pods: init containers and sidecars 🔥 HIGH

### Analogies
- ✈️ **Airport (init containers):** check-in → security → passport control. **In order, one at a time**, each must succeed before the next. Only then do you board (main containers start). If security fails, you go back and try again (the pod restarts the init container).
- 🎬 **Cinema (init containers):** the cleaners clean the hall, then the technician tests the sound, *then* doors open.
- 🏎 **Rally (sidecar):** the co-driver sits next to the driver the **whole** race, reading notes. Starts before the driver, leaves after.
- 🍽 **Restaurant (sidecar):** the dishwasher works all shift next to the chef. The chef cooks (app), the dishwasher deals with the dirty plates (logs).
- ⚽ **Football (adapter/ambassador):** the translator next to a foreign coach (adapter converts the format). The agent who talks to other clubs for the player (ambassador proxies outgoing connections).

### Kinds of extra containers

| Type | Where in YAML | Runs | Example |
|---|---|---|---|
| **Init container** | `initContainers` (no restartPolicy) | before app, **sequentially**, must exit 0 | wait for DB, download config, fix permissions |
| **Native sidecar** (GA 1.33) | `initContainers` with `restartPolicy: Always` | starts before app, **keeps running**, stops after app | log shipper, proxy |
| **Classic sidecar** | second entry in `containers` | in parallel with app | same, old style (no start order guarantee) |

```yaml
apiVersion: v1
kind: Pod
metadata: {name: web}
spec:
  initContainers:
  - name: wait-for-db                      # 1st: blocks until DNS name resolves
    image: busybox:1.36
    command: ['sh', '-c', 'until nslookup db.default.svc.cluster.local; do echo waiting; sleep 2; done']
  - name: log-shipper                      # 2nd: native sidecar, starts and STAYS
    image: busybox:1.36
    restartPolicy: Always                  # ← this one line makes it a sidecar
    command: ['sh', '-c', 'tail -F /var/log/app/app.log']
    volumeMounts: [{name: logs, mountPath: /var/log/app}]
  containers:
  - name: app
    image: busybox:1.36
    command: ['sh', '-c', 'while true; do date >> /var/log/app/app.log; sleep 2; done']
    volumeMounts: [{name: logs, mountPath: /var/log/app}]
  volumes:
  - name: logs
    emptyDir: {}                           # shared "table" between the containers
```

Status you'll see: `Init:0/2` → `Init:1/2` → `PodInitializing` → `Running`. `Init:CrashLoopBackOff` = an init container keeps failing → `k logs web -c wait-for-db`.

**Exam pattern:** "Add a sidecar to deployment X that streams /var/log/app.log." → `k edit deploy x` (or get -o yaml, edit, replace), add an emptyDir, mount it in **both** containers, add the sidecar with `restartPolicy: Always` in `initContainers`. Verify with `k logs deploy/x -c <sidecar>`.

⚠️ Traps:
- You **can't add containers to a running Pod** (`k edit` refuses). For a bare pod: `k get po x -o yaml > p.yaml`, edit, `k replace --force -f p.yaml`. For a deployment: just edit the template.
- `k logs pod` with several containers → error "a container name must be specified" → use `-c`.
- Containers in one pod share **network** (talk on `localhost`) and can share **volumes**, but **not** the filesystem by default.

---

## 6. Probes (health checks) 🔥 HIGH

### Analogies
- 🍽 **Restaurant:**
  - **startupProbe:** "Is the kitchen even open yet?" Don't judge a chef who is still putting on the apron.
  - **readinessProbe:** "Can this chef take orders right now?" If not, the waiter stops sending orders to them (removed from Service endpoints), but nobody is fired.
  - **livenessProbe:** "Is the chef still alive / not frozen?" If not, **replace the chef** (container restart).
- 🚗 **Car:** startup = engine warming up in winter; readiness = "can I drive yet?"; liveness = "engine died → restart it".
- ✈️ **Airport:** readiness = the gate is open for boarding; liveness = the plane's systems are working.

```yaml
containers:
- name: web
  image: nginx:1.27
  ports:
  - name: http
    containerPort: 80
  startupProbe:                 # liveness/readiness wait until this succeeds once
    httpGet: {path: /, port: http}
    failureThreshold: 30        # 30 × 5s = up to 150s to start
    periodSeconds: 5
  readinessProbe:
    httpGet: {path: /, port: 80}
    initialDelaySeconds: 5      # wait before the first check
    periodSeconds: 5            # check every 5s
    failureThreshold: 3         # 3 fails in a row → NotReady
  livenessProbe:
    tcpSocket: {port: 80}       # other types: exec: {command: [cat, /tmp/healthy]}, grpc: {port: 9000}
    periodSeconds: 10
    timeoutSeconds: 1
    failureThreshold: 3         # 3 fails in a row → container restarted
```

| Symptom | Likely probe problem |
|---|---|
| Pod `Running` but `READY 0/1`, Service has no endpoints | readiness fails (wrong port/path) |
| `RESTARTS` keeps climbing, logs look fine | liveness fails (wrong port/path or too aggressive) |
| Restarts only during slow startup | missing startupProbe or too small `initialDelaySeconds` |

`k describe po` → Events show `Readiness probe failed: ... connection refused` / `Liveness probe failed: HTTP probe failed with statuscode: 404`.

---

## 7. Resources: requests, limits, LimitRange, ResourceQuota 🔥 HIGH

### Analogies
- 🅿️ **Parking:** `requests` = a **reserved** parking spot. The scheduler only sends you to a lot (node) with a free reserved spot. `limits` = the barrier height: CPU over the limit → you're slowed down (throttled), memory over the limit → you're towed away (OOMKilled).
- 🎬 **Cinema:** requests = seats you booked. limits = the maximum the fire marshal allows you.
- 📱 **Family phone plan (ResourceQuota):** the whole family (namespace) shares 20 GB. **LimitRange** = the rule "each child gets 2 GB by default and at most 5 GB".
- ⚽ **Football:** ResourceQuota = the squad limit of 25 players per club (namespace). LimitRange = "each player's wage must be between X and Y, default Z".

### Units
- CPU: `1` = 1 core, `500m` = half a core, `0.1` = `100m`. **`cpu: "50"` = 50 cores** (that's `break.sh 10`).
- Memory: `Mi`/`Gi` = powers of 2 (1Mi = 1,048,576 bytes). `M`/`G` = powers of 10. `128m` memory = 0.128 bytes (a classic typo).

```yaml
resources:
  requests: {cpu: 250m, memory: 128Mi}   # used by the SCHEDULER
  limits:   {cpu: 500m, memory: 256Mi}   # enforced by the KUBELET/kernel
```
- The scheduler compares requests with the node's **Allocatable** (capacity minus system/kubelet reservations), not its Capacity.
- Over the CPU limit → **throttled**. Over the memory limit → **OOMKilled** (exit 137).
- Only limits set → requests default to the limits.

### LimitRange (per container/pod defaults and min/max in ONE namespace)
```yaml
apiVersion: v1
kind: LimitRange
metadata: {name: defaults, namespace: dev}
spec:
  limits:
  - type: Container
    default:        {cpu: 500m, memory: 256Mi}   # default LIMIT if the container sets none
    defaultRequest: {cpu: 100m, memory: 128Mi}   # default REQUEST if the container sets none
    max:            {cpu: "1",  memory: 1Gi}
    min:            {cpu: 50m,  memory: 64Mi}
```
Applied **only when pods are created** (LimitRanger admission). Existing pods aren't changed.
Violations → the pod is **rejected**: `forbidden: maximum cpu usage per Container is 1`. A `type: PersistentVolumeClaim` entry can cap PVC sizes too (`max: {storage: 5Gi}`).

### ResourceQuota (totals for the whole namespace)
```bash
k create quota dev-q -n dev --hard=pods=10,requests.cpu=2,requests.memory=2Gi,limits.cpu=4,limits.memory=4Gi,services=5,persistentvolumeclaims=3
k describe quota -n dev          # Used vs Hard
```
Other useful keys: `count/deployments.apps: "2"` (any kind: `count/<resource>.<group>`), `services.nodeports: "0"`, `requests.storage: 10Gi`, `configmaps: "10"`.

| | LimitRange | ResourceQuota |
|---|---|---|
| Scope | **per container/pod/PVC** | **total for the namespace** |
| Sets defaults? | ✅ | ❌ |
| 🍽 | the size of each plate | the budget for the whole party |
⚠️ If a quota covers `requests.cpu`, **every new pod must set a CPU request** (or get one from a LimitRange), otherwise: `forbidden: failed quota: must specify requests.cpu`. Deployments then show 0 pods and the error is on the **ReplicaSet** events: `k describe rs`.

### Exam pattern: "split the node's resources evenly across N replicas"
```bash
k describe node node01 | grep -A6 Allocatable      # e.g. cpu 2, memory 3800Mi
k describe node node01 | grep -A10 "Allocated resources"   # what's already requested
# leave some room for overhead / other pods, divide by replicas, e.g. 3 replicas → cpu 600m, memory 1100Mi each
k scale deploy wp --replicas=0          # stop the old pods first (avoids Pending during the change)
k edit deploy wp                        # set requests (and limits if asked) for containers AND initContainers
k scale deploy wp --replicas=3
k get po -o wide                        # all Running?
```

### QoS classes (who gets evicted first when a node runs out of memory)
| Class | Rule | Eviction order |
|---|---|---|
| Guaranteed | every container has requests = limits for cpu AND memory | last |
| Burstable | at least one request/limit set | middle |
| BestEffort | nothing set | first |

---

## 8. Autoscaling 🔥 HIGH (HPA) / 🧊 LOW (VPA)

### Analogies
- 🍽 **Restaurant (HPA):** lunch rush, so open more tables and call in more waiters. Quiet evening, so send some home. HPA adds/removes **pods** (horizontal = more copies).
- 🚗 **Car (VPA):** instead of more cars, swap in a **bigger engine** (vertical = more CPU/memory for the same pod).
- 🎬 **Cinema:** a blockbuster opens, so open extra halls (HPA). Or move the film to the IMAX hall (VPA).
- ⚽ **Stabilization window:** the coach doesn't substitute players the second they look tired. They wait 5 minutes to be sure (`scaleDown.stabilizationWindowSeconds`, default 300s).

HPA needs **metrics-server** (your `up.sh` installs it) and **CPU requests** on the pods (utilization % = usage / request).

**How it decides:** every ~15 s → `desired = ceil(current × currentUtil / targetUtil)` → updates `replicas` on the Deployment. Example: 2 pods at 90% with target 50% → ceil(2 × 90/50) = 4.

```bash
k autoscale deploy php --min=1 --max=5 --cpu-percent=50 $do > hpa.yaml   # newer kubectl may prefer --cpu=50% (see k autoscale -h)
k get hpa                         # TARGETS <unknown>/50% → metrics-server missing OR no cpu request
```
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: php}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: php}
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target: {type: Utilization, averageUtilization: 50}
  - type: Resource
    resource:
      name: memory
      target: {type: AverageValue, averageValue: 200Mi}
  behavior:                                # 🔥 exam has asked for this
    scaleDown:
      stabilizationWindowSeconds: 30       # default 300
      policies:
      - {type: Pods, value: 1, periodSeconds: 60}   # remove at most 1 pod per minute
    scaleUp:
      stabilizationWindowSeconds: 0
```
⚠️ `kubectl autoscale` **can't set `behavior`**. Generate with `$do`, add `behavior`, then apply.
Docs page to bookmark: "HorizontalPodAutoscaler Walkthrough" and "Horizontal Pod Autoscaling" (has the `behavior` examples).

| HPA symptom | Cause |
|---|---|
| TARGETS `<unknown>/50%` | metrics-server missing/broken, **or** no CPU request on the containers |
| Doesn't scale down right away | stabilization window (default 5 min) |
| Never goes over N | `maxReplicas`, or a ResourceQuota blocks new pods |

**VPA** 🧊: a separate add-on (CRD `VerticalPodAutoscaler`), modes `Off` (recommend only), `Initial`, `Recreate`, `InPlaceOrRecreate` (newer). Know it exists.
**In-place pod resize** 🟡: newer Kubernetes can change CPU/memory of a running container without a restart, via the `resize` subresource (`k patch pod x --subresource resize -p ...`) and `resizePolicy` per container. Know the idea.

---

## 9. Jobs and CronJobs, the fields that matter 🟡 MEDIUM

### Analogies
- 🍽 **Job:** a catering order: cook 50 meals (`completions`), 5 cooks at a time (`parallelism`). If a cook burns a dish, retry, but give up after 4 burnt dishes (`backoffLimit`). The whole order must be done in 2 hours (`activeDeadlineSeconds`).
- ⏰ **CronJob:** the cleaning crew comes every night at 02:00. If last night's cleaning is still going: `Allow` (send another crew anyway), `Forbid` (skip tonight), `Replace` (stop the old crew, send a new one).

```yaml
apiVersion: batch/v1
kind: CronJob
metadata: {name: backup}
spec:
  schedule: "*/5 * * * *"           # min hour day-of-month month day-of-week
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  startingDeadlineSeconds: 100
  suspend: false
  jobTemplate:
    spec:
      completions: 1
      parallelism: 1
      backoffLimit: 4                # retries before the Job is Failed (default 6)
      activeDeadlineSeconds: 120     # hard time limit for the whole Job
      ttlSecondsAfterFinished: 600   # auto-delete finished Job
      template:
        spec:
          restartPolicy: OnFailure   # or Never. NOT Always
          containers:
          - name: b
            image: busybox:1.36
            command: ["sh", "-c", "date; echo backup done"]
```
```bash
k create cronjob backup --image=busybox:1.36 --schedule="*/5 * * * *" $do -- sh -c 'date'
k create job manual-run --from=cronjob/backup       # run it NOW to test (exam trick)
k get jobs,po; k logs job/manual-run
```

---

## 10. Pod termination (graceful shutdown) 🟡 MEDIUM

### Analogy
🎬 **Cinema closing time:** the lights come on (SIGTERM), people get 30 seconds to leave (`terminationGracePeriodSeconds: 30`), then security removes whoever is left (SIGKILL). A `preStop` hook = the announcement "please take your rubbish with you" before the lights come on.

Order: pod marked Terminating → removed from Service endpoints → `preStop` hook runs → SIGTERM → wait grace period → SIGKILL.
```yaml
spec:
  terminationGracePeriodSeconds: 30
  containers:
  - name: web
    image: nginx:1.27
    lifecycle:
      postStart: {exec: {command: ["sh", "-c", "echo started > /tmp/started"]}}
      preStop:   {exec: {command: ["sh", "-c", "nginx -s quit; sleep 5"]}}
```
`k delete po x $now` skips the wait (force). Use it in the exam to save time, never on stateful things in real life.

---

## 11. Self-check (answer without looking)

1. A deployment has 10 replicas, maxSurge 30%, maxUnavailable 30%. Max total pods and min available pods during a rollout?
2. Image has `ENTRYPOINT ["python","app.py"]` and `CMD ["--port","80"]`. Pod sets only `command: ["python","other.py"]`. What runs?
3. You updated a ConfigMap used via `envFrom`. Pods still see the old values. Why, and the fastest fix?
4. Pod shows `CreateContainerConfigError`. First 2 things you check?
5. Pod is `Running` but `0/1 READY` and the Service has no endpoints. Which probe, and what do you look at?
6. How do you make an initContainer behave as a sidecar?
7. `k get hpa` shows `<unknown>/50%`. Two possible causes?
8. ResourceQuota with `requests.cpu` exists, you create a deployment without requests. What do you see, and where is the error?
9. What QoS class does a pod get with `requests: cpu 100m` and no limits?
10. A CronJob must not start a new run if the previous one is still running. Which field and value?
11. How do you run a CronJob immediately to test it?
12. You must add a container to an existing bare pod. How?
13. Which namespace holds node heartbeats, and as what kind of object?
14. What's wrong with `volumes: - name: s  secret: {name: db}`?
15. `echo 'pass' | base64` was used to create a secret, and the DB login fails. Why?
16. LimitRange vs ResourceQuota in one sentence each.

<details><summary>Answers</summary>

1. Surge 30% of 10 = 3 (round up) → max 13. Unavailable 30% of 10 = 3 (round down) → min 7.
2. `python other.py` only. Setting `command` drops the image CMD.
3. Env vars are read once at container start. `k rollout restart deploy/x`.
4. `k describe po` events (which ConfigMap/Secret/key is missing), then `k get cm,secret` in that namespace and compare key names.
5. Readiness probe. `k describe po` events ("Readiness probe failed"), compare probe port/path with what the app listens on.
6. Put it in `initContainers` with `restartPolicy: Always`.
7. metrics-server not running/working, or the pods have no CPU request.
8. Deployment shows 0/N ready, no pods. `k describe rs <new-rs>` shows `forbidden: failed quota ... must specify requests.cpu`.
9. Burstable.
10. `concurrencyPolicy: Forbid`.
11. `k create job test --from=cronjob/<name>`.
12. Export YAML, edit, `k replace --force -f pod.yaml` (delete + recreate).
13. `kube-node-lease`, as `Lease` objects.
14. For secret volumes the field is `secretName`, not `name`.
15. Without `-n`, echo adds a newline, so the stored value is `pass\n`.
16. LimitRange = per-container defaults and min/max. ResourceQuota = the total budget for the namespace.
</details>

---

## 12. Mini-drills in your kind lab (≈60 min)

```bash
# A. Rollout math (10 min): deploy 4 replicas nginx:1.27 with maxSurge 1 / maxUnavailable 0,
#    k set image to nginx:1.28 and run `k get rs -w` in a second terminal. Then set a BAD image (nginx:nope),
#    watch the rollout stall, `k rollout undo`, and check history with a change-cause annotation.

# B. ConfigMap update behaviour (10 min): one pod with envFrom + a volume mount of the same CM.
#    Edit the CM. After ~1 min: `k exec` → cat the file (new) vs `env` (old). Then rollout restart.

# C. Native sidecar (10 min): drill 2.5 in drills/DRILLS.md, then add it to an existing DEPLOYMENT instead of a pod.

# D. Probes (10 min): deployment with readinessProbe on port 8080 (wrong). Expose it. See empty endpoints.
#    Fix the port, watch endpoints appear: `k get endpointslices -w`.

# E. Quota trap (10 min): ns q, quota requests.cpu=1. Create deploy without requests → find the error on the RS.
#    Add a LimitRange with defaultRequest → `k rollout restart` → pods appear.

# F. HPA with behavior (10 min): drill 2.3, then convert it to YAML with scaleDown.stabilizationWindowSeconds: 30.
#    Load: k run load --image=busybox:1.36 --rm -it -- sh -c "while true; do wget -qO- http://php; done"
```
