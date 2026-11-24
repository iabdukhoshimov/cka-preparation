---
tags:
  - cka/architecture
---

← [[03-application-lifecycle]] · [[00 Home|🏠 Home]] · [[05-storage]] →

# 04: Security: certificates, kubeconfig, RBAC, ServiceAccounts, security contexts, secrets at rest

Domain: mostly **Cluster Architecture, Installation & Configuration (25%)** (RBAC is in almost every exam), plus security contexts inside workload tasks.
NetworkPolicy is a security topic too, but it lives in [[06-networking]]. Admission controllers are in [[02-scheduling-admission-observability]].

Tags: 🔥 HIGH · 🟡 MEDIUM · 🧊 LOW

---

## The big picture in one story: the airport ✈️

Every request to the API server goes through the same checks as a passenger at an airport:

```
kubectl / pod / kubelet
   │
   ▼
① Authentication (AuthN)  "WHO are you?"           ✈️ passport check        → certs, tokens, OIDC
② Authorization  (AuthZ)  "WHAT may you do?"        ✈️ boarding pass for THIS flight → RBAC (+ Node authorizer)
③ Admission               "is the OBJECT okay?"     ✈️ security scanner, bag re-tagging → see note 02
④ etcd                    stored                    ✈️ you're on the plane
```

| Concept | ✈️ Airport | 🚗 Car / 🅿️ Parking | ⚽ Football | 🍽 Restaurant |
|---|---|---|---|---|
| CA (certificate authority) | the government that issues passports | the DMV that issues driving licenses | the federation that issues player licenses | the health inspector who certifies the kitchen |
| Client certificate | your passport | your driving license | your player license | the chef's certificate |
| kubeconfig | your travel wallet: passports + tickets + which flight you're on now | your keyring: several car keys, one in the ignition | the coach's folder: teams, players, today's match | — |
| User (no object in k8s!) | a traveller. The airport has no "traveller list", it trusts the passport | — | a fan: no account, just a valid ticket | a guest |
| ServiceAccount | airline crew badge (for machines/pods) | the company car's fleet card | the club's staff badge | the delivery robot's access card |
| Role / ClusterRole | "Gate 5 boarding pass" / "all-terminals crew pass" | key for one garage / master key for all garages | squad list for one match / league-wide license | kitchen key / keys to every branch |
| RoleBinding / ClusterRoleBinding | the airline hands that pass to a person | handing the key to a driver | putting a player on the team sheet | giving the key to a staff member |
| securityContext | cabin rules: "no smoking, seatbelt on, you're not the pilot" | speed limiter, child lock | rules on kit: no jewellery, shin guards on | hygiene rules: hairnet, no jewellery |
| Secret encryption at rest | luggage locked in the hold | documents in a locked glovebox | — | recipes in a locked safe |

### Authentication: where does "who you are" come from? 🟡 MEDIUM
**Kubernetes has NO "User" objects.** You can't `k create user`. A "user" is just a **name the API server trusts from a credential**:

| Method | Identity comes from | Used by |
|---|---|---|
| **X.509 client certificate** | **CN = username**, **O = group(s)** | admins, kubeadm components, kubelets (`system:node:<name>`, group `system:nodes`) |
| **ServiceAccount token** (JWT) | `system:serviceaccount:<ns>:<name>` | pods / programs inside the cluster |
| OIDC | the token's claims | SSO setups (Google, Keycloak...) |
| static token file, basic auth | deprecated/removed. Ignore | |

Special groups: `system:masters` (**full admin, bypasses RBAC entirely**), `system:authenticated`, `system:unauthenticated`, `system:serviceaccounts`, `system:serviceaccounts:<ns>`.

---

## 1. TLS certificates in a kubeadm cluster 🟡 MEDIUM (cert paths in troubleshooting are 🔥)

> [!example]+ Analogies
> - ✈️ **Passports:** the **CA** (`ca.crt` + `ca.key`) is the government. It signs passports (certificates). Anyone who trusts the government (has `ca.crt`) trusts every passport it signed. Lose `ca.key` and anyone can print fake passports.
> - 🚗 **License:** a cert says "this is **Bob** (CN), in group **developers** (O), valid until **2027**". The API server reads CN as the **username** and O as the **groups**.

### Where everything lives (kubeadm)
```
/etc/kubernetes/pki/
├── ca.crt, ca.key                     # cluster CA (signs everything below except etcd)
├── apiserver.crt/.key                 # API server's SERVING cert (SANs: IPs + names of the API)
├── apiserver-kubelet-client.crt/.key  # API server → kubelet (client)
├── apiserver-etcd-client.crt/.key     # API server → etcd (client)
├── front-proxy-ca.*, front-proxy-client.*   # aggregation layer
├── sa.key, sa.pub                     # signs/verifies ServiceAccount tokens (not a cert)
└── etcd/
    ├── ca.crt, ca.key                 # SEPARATE CA for etcd
    ├── server.crt/.key                # etcd serving
    ├── peer.crt/.key                  # etcd ↔ etcd
    └── healthcheck-client.*
/etc/kubernetes/admin.conf, super-admin.conf   # kubeconfigs (certs embedded)
/etc/kubernetes/controller-manager.conf, scheduler.conf, kubelet.conf
/var/lib/kubelet/pki/kubelet-client-current.pem # kubelet's own client cert (auto-rotated)
```

### Read a cert (exam: "what's the CN / issuer / expiry of the API server cert?")
```bash
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -E 'Subject:|Issuer:|Not After|DNS:'
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate
kubeadm certs check-expiration            # all certs + CAs, with RESIDUAL TIME
kubeadm certs renew all                   # or: renew apiserver. Then restart the control-plane static pods
                                          # (move manifests out of /etc/kubernetes/manifests and back, or wait)
```

### The flags that reference certs (and get broken in troubleshooting tasks)
| Component | Flag | Points to |
|---|---|---|
| kube-apiserver | `--client-ca-file` | `/etc/kubernetes/pki/ca.crt` |
| kube-apiserver | `--tls-cert-file` / `--tls-private-key-file` | `apiserver.crt` / `.key` |
| kube-apiserver | `--etcd-cafile` | `/etc/kubernetes/pki/etcd/ca.crt` |
| kube-apiserver | `--etcd-certfile` / `--etcd-keyfile` | `apiserver-etcd-client.crt` / `.key` |
| kube-apiserver | `--kubelet-client-certificate` / `-key` | `apiserver-kubelet-client.*` |
| etcd | `--cert-file`, `--key-file`, `--trusted-ca-file`, `--peer-*` | `etcd/server.*`, `etcd/ca.crt`, `etcd/peer.*` |
| kubelet | `clientCAFile` in `/var/lib/kubelet/config.yaml` | `/etc/kubernetes/pki/ca.crt` |

> [!danger]
> Troubleshooting trick: **`ls` the path from the flag**. A typo (`ca-cert.crt`, `apiserver-etcd.crt`) is the classic broken-cluster task. `crictl logs` will say `no such file or directory`.

---

## 2. Creating a user with the CertificateSigningRequest API 🔥 HIGH

### Analogy
✈️ You fill in a **passport application** (CSR) and hand it to the passport office (API server). An official **approves** it (`k certificate approve`), and the office hands back your **passport** (signed cert). You put it in your travel wallet (kubeconfig).

```bash
# 1. private key + CSR. CN = username, O = group (optional)
openssl genrsa -out jane.key 2048
openssl req -new -key jane.key -out jane.csr -subj "/CN=jane/O=developers"

# 2. CSR object (copy the YAML from docs: "Certificates and Certificate Signing Requests" → "Normal user")
cat <<EOF > csr.yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: jane
spec:
  request: $(base64 -w0 < jane.csr)        # ONE line, no wraps (-w0)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400                  # 1 day (optional)
  usages:
  - client auth
EOF
k apply -f csr.yaml
k get csr                                   # CONDITION: Pending
k certificate approve jane                  # (or deny)
k get csr jane -o jsonpath='{.status.certificate}' | base64 -d > jane.crt

# 3. kubeconfig entries
k config set-credentials jane --client-key=jane.key --client-certificate=jane.crt --embed-certs=true
k config set-context jane --cluster=kind-cka --user=jane --namespace=dev
k --context=jane get pods                   # Forbidden → good! AuthN works, RBAC not given yet (section 4)
```
> [!warning]
> "Forbidden" (403) = **authenticated but not authorized** → RBAC. "Unauthorized" (401) = the cert/token itself is bad → AuthN.

---

## 3. kubeconfig 🔥 HIGH

> [!example]+ Analogies
> - 🔑 **Keyring:** `clusters` = the cars you may drive (address + the CA to trust it). `users` = your keys/licenses. `contexts` = "this key with this car (and this default garage = namespace)". `current-context` = the key in the ignition right now.
> - ✈️ **Travel wallet:** clusters = airports, users = passports, contexts = "this passport at this airport", current-context = the flight you're on.

```yaml
apiVersion: v1
kind: Config
clusters:
- name: prod
  cluster:
    server: https://10.0.0.10:6443                # 🔥 wrong port (6433, 6444) = classic broken task
    certificate-authority-data: <base64 ca.crt>  # or certificate-authority: /path/ca.crt
users:
- name: admin
  user:
    client-certificate-data: <base64>
    client-key-data: <base64>
contexts:
- name: admin@prod
  context: {cluster: prod, user: admin, namespace: default}
current-context: admin@prod
```

```bash
k config view [--minify] [--raw]            # --minify = only current context
k config get-contexts
k config current-context
k config use-context admin@prod
k config set-context --current --namespace=dev   # your `kn dev` function
k --kubeconfig=/root/other.conf get nodes        # use another file once
export KUBECONFIG=~/.kube/config:/root/other.conf # merge several
```
Lookup order: `--kubeconfig` flag → the `$KUBECONFIG` env var (can be a list `a:b`) → `~/.kube/config`.

On a kubeadm control plane: `/etc/kubernetes/admin.conf` (group `kubeadm:cluster-admins`, the normal admin), `super-admin.conf` (`system:masters`, break-glass only), `controller-manager.conf`, `scheduler.conf`, and `kubelet.conf` on every node.

> [!danger]
> Troubleshooting: `kubectl` says "connection refused" or "x509: certificate signed by unknown authority" → check the `server:` URL and port (6443) and the CA in the kubeconfig **before** blaming the cluster.

---

## 4. RBAC 🔥 HIGH (in nearly every exam)

> [!example]+ Analogies
> - 🏨 **Hotel keycards:**
>   - **Role** = a keycard programmed for "rooms 101–110 on floor 1" (one namespace).
>   - **ClusterRole** = a keycard *design* for "all floors" or for "the roof" (cluster-wide things like nodes).
>   - **RoleBinding** = handing a programmed card to a guest **for one floor**. You can hand a "ClusterRole card" via a RoleBinding: then it only opens doors **on that floor**.
>   - **ClusterRoleBinding** = handing the card for **the whole hotel**.
> - ⚽ **Football:** Role = "may play in today's match"; ClusterRole = "may play in any match in the league"; the binding = the team sheet with your name on it.
> - 🍽 **Restaurant:** verbs are what you may do with the menu (`get` = read one dish, `list` = read the whole menu, `create` = add a dish, `delete` = remove one).

**RBAC only ALLOWS. There's no "deny" rule.** No rule matches → denied.

### The 4 combinations
| Binding | Role type | Result |
|---|---|---|
| RoleBinding (ns A) | Role (ns A) | permissions in ns A |
| RoleBinding (ns A) | ClusterRole | the ClusterRole's rules **only in ns A** (reuse one ClusterRole in many ns) |
| ClusterRoleBinding | ClusterRole | permissions in **all** namespaces + cluster-scoped resources |
| ClusterRoleBinding | Role | ❌ not possible |

Cluster-scoped resources (nodes, PVs, namespaces, storageclasses, CRDs, clusterroles...) can **only** be granted through ClusterRole + **ClusterRoleBinding**.

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: pod-reader, namespace: dev}
rules:
- apiGroups: [""]                    # "" = core group (pods, services, cm, secrets, pvc...)
  resources: ["pods", "pods/log"]    # subresource pods/log is SEPARATE from pods (also pods/exec)
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]                # deployments, statefulsets, daemonsets, replicasets
  resources: ["deployments"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["configmaps"]
  resourceNames: ["app-cfg"]         # only THIS object
  verbs: ["get", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: jane-pod-reader, namespace: dev}
subjects:
- kind: User
  name: jane
  apiGroup: rbac.authorization.k8s.io
- kind: ServiceAccount
  name: ci-bot
  namespace: dev                     # SA subject needs its namespace
- kind: Group
  name: developers
  apiGroup: rbac.authorization.k8s.io
roleRef:                             # IMMUTABLE. To change the role: delete and recreate the binding
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

Which apiGroup? → `k api-resources | grep -i deploy` (the APIVERSION column: `apps/v1` → group `apps`; `v1` → `""`; `networking.k8s.io/v1` → `networking.k8s.io`).

### API groups to know 🔥 (a wrong apiGroup = the rule silently grants nothing)
| Resources | apiGroup |
|---|---|
| pods, services, endpoints, configmaps, secrets, namespaces, nodes, PVs, PVCs, serviceaccounts, events | `""` (core) |
| deployments, replicasets, daemonsets, statefulsets | `apps` |
| jobs, cronjobs | `batch` |
| ingresses, networkpolicies | `networking.k8s.io` |
| roles, rolebindings, clusterroles, clusterrolebindings | `rbac.authorization.k8s.io` |
| storageclasses | `storage.k8s.io` |
| horizontalpodautoscalers | `autoscaling` |
| poddisruptionbudgets | `policy` |
| CRDs | `apiextensions.k8s.io` |
| gateways, httproutes | `gateway.networking.k8s.io` |

`k api-resources -o wide` also shows the **VERBS** each resource supports.
Verbs: `get list watch create update patch delete deletecollection`, plus special ones: `use`, `bind`, `escalate`, `impersonate`, `approve`. `"*"` = everything.

### Imperative (faster, fewer typos)
```bash
k -n dev create role pod-reader --verb=get,list,watch --resource=pods,pods/log
k -n dev create role deploy-mgr --verb=create,get,list,update,delete --resource=deployments.apps
k -n dev create role cm-one --verb=get --resource=configmaps --resource-name=app-cfg
k -n dev create rolebinding jane-pr --role=pod-reader --user=jane
k -n dev create rolebinding ci-pr --clusterrole=view --serviceaccount=dev:ci-bot   # built-in ClusterRole, one ns
k create clusterrole node-reader --verb=get,list,watch --resource=nodes
k create clusterrolebinding jane-nodes --clusterrole=node-reader --user=jane
```
(`--resource=deployments` usually figures out the `apps` group by itself. `deployments.apps` is the explicit form.)

### Built-in ClusterRoles (reuse them instead of writing your own)
| ClusterRole | Gives |
|---|---|
| `cluster-admin` | everything |
| `admin` | everything in a namespace incl. RBAC (via a RoleBinding), but not quotas/the namespace itself |
| `edit` | read/write most objects, no RBAC, **can read secrets** |
| `view` | read-only, **no secrets** |

Aggregated ClusterRoles: `aggregationRule.clusterRoleSelectors` merges the rules of ClusterRoles with matching labels. That's how `admin/edit/view` grow when CRDs are added.

### Verify (always, unverified = lost points)
```bash
k auth can-i list pods -n dev --as=jane                                  # yes/no
k auth can-i create deployments -n dev --as=system:serviceaccount:dev:ci-bot
k auth can-i get pods/log -n dev --as=jane
k auth can-i '*' '*' --as=jane                                            # is she admin?
k auth can-i --list -n dev --as=jane                                      # everything she can do
k auth can-i get nodes --as=x --as-group=developers                       # test a GROUP's rights
k describe rolebinding -n dev ; k get rolebindings,clusterrolebindings -A -o wide | grep jane
k auth whoami                                                             # who am I right now?
```

> [!warning]
> Traps:
> - `--serviceaccount=dev:ci-bot` (namespace **colon** name). In `--as` it's `system:serviceaccount:dev:ci-bot`.
> - RoleBinding in the **wrong namespace** = the classic silent failure. The binding's namespace decides where it works.
> - `deployments` needs apiGroup `apps`. With `[""]` it silently grants nothing.
> - `pods/exec`, `pods/log`, `deployments/scale` are subresources and must be listed explicitly.
> - You can't create a role with **more** permissions than you have yourself (privilege escalation prevention).

---

## 5. ServiceAccounts 🔥 HIGH

> [!example]+ Analogies
> - 🤖 **Robot staff badge:** users are humans (outside the cluster, no object). ServiceAccounts are **identities for pods/programs** and they ARE objects in a namespace.
> - 🚗 **Fleet card:** the company car (pod) has a fleet card (SA token) to pay at the pump (call the API). Every namespace has a `default` card with almost no credit.
> - 🎬 **Cinema staff badge:** the projector robot needs a badge to open the projection room. You give it a badge (SA) and program the doors that badge opens (RBAC).

Facts:
- Every namespace gets a `default` SA automatically. Pods without `serviceAccountName` use it.
- The kubelet mounts a **short-lived, auto-rotated projected token** at `/var/run/secrets/kubernetes.io/serviceaccount/` (`token`, `ca.crt`, `namespace`).
- Since 1.24, **no Secret with a token is created automatically** for an SA.

```bash
k -n dev create sa ci-bot
k -n dev create token ci-bot --duration=1h          # print a token (e.g. for curl or a kubeconfig)
k -n dev set serviceaccount deploy/web ci-bot       # change the SA of a deployment (rolls pods)
```
```yaml
spec:
  serviceAccountName: ci-bot              # can't be changed on a RUNNING pod → recreate it
  automountServiceAccountToken: false     # don't mount a token (pod doesn't call the API) — also settable on the SA
---
# Legacy long-lived token (only if a task explicitly asks for a token Secret)
apiVersion: v1
kind: Secret
metadata:
  name: ci-bot-token
  namespace: dev
  annotations:
    kubernetes.io/service-account.name: ci-bot
type: kubernetes.io/service-account-token
```

**Exam pattern:** "Create SA `X` in ns `Y`, a Role that can only list pods, bind it, and make deployment `Z` use the SA." → create sa → create role → create rolebinding with `--serviceaccount=Y:X` → `k set serviceaccount deploy/Z X -n Y` → verify with `auth can-i --as=system:serviceaccount:Y:X`.

Test from inside a pod:
```bash
k exec -it pod -- sh
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
wget -qO- --no-check-certificate --header "Authorization: Bearer $TOKEN" https://kubernetes.default.svc/api/v1/namespaces/dev/pods
# with curl (e.g. image curlimages/curl), verifying the server against the mounted CA:
curl -s --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/dev/pods
```
403 in the JSON = the token works but RBAC says no. 401 = bad token.

---

## 6. Security contexts 🔥 HIGH

> [!example]+ Analogies
> - ✈️ **Cabin rules:** you're a passenger, not the pilot (`runAsNonRoot`, `runAsUser: 1000`). You can't open the cockpit (`allowPrivilegeEscalation: false`). You can look at the safety card but not write on it (`readOnlyRootFilesystem`).
> - 🚗 **Child lock + speed limiter:** the car works, but some doors and speeds are blocked (dropped **capabilities**).
> - 🍽 **Kitchen:** a trainee may use knives (`NET_BIND_SERVICE`) but not the gas main (`SYS_ADMIN`). `privileged: true` = the trainee gets the keys to the whole building. Almost never what you want.

```yaml
apiVersion: v1
kind: Pod
metadata: {name: secure}
spec:
  securityContext:              # POD level → applies to all containers
    runAsUser: 1000
    runAsGroup: 3000
    fsGroup: 2000               # volumes are group-owned by 2000 (only at pod level!)
    runAsNonRoot: true          # refuse to start if the image would run as root
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "id; sleep 3600"]
    securityContext:            # CONTAINER level → wins over pod level for the same field
      runAsUser: 2000
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      privileged: false
      capabilities:             # ONLY at container level
        add: ["NET_ADMIN", "SYS_TIME"]
        drop: ["ALL"]
```
Verify: `k exec secure -- id` → `uid=2000 gid=3000 groups=2000`.

| Field | Pod level | Container level |
|---|---|---|
| runAsUser / runAsGroup / runAsNonRoot | ✅ | ✅ (wins) |
| fsGroup, supplementalGroups, sysctls | ✅ | ❌ |
| capabilities, privileged, allowPrivilegeEscalation, readOnlyRootFilesystem | ❌ | ✅ |
| seccompProfile | ✅ | ✅ |

> [!warning]
> Traps:
> - `capabilities` written at pod level = validation error ("unknown field").
> - Capability names without the `CAP_` prefix: `NET_ADMIN`, not `CAP_NET_ADMIN`.
> - `readOnlyRootFilesystem: true` + an app that writes to `/tmp` → crash. Mount an `emptyDir` on `/tmp`.
> - `runAsNonRoot: true` + image runs as root and no `runAsUser` → `CreateContainerConfigError: container has runAsNonRoot and image will run as root`.

---

## 7. Pod Security Admission (Pod Security Standards) 🟡 MEDIUM

### Analogy
🎬 **Film age ratings per hall:** each hall (namespace) has a label: `privileged` (anything goes), `baseline` (no obviously dangerous stuff), `restricted` (strict, like a kids' screening). The doorman (admission plugin) checks every pod against the hall's rating.

Three **modes**: `enforce` (reject), `audit` (write to audit log), `warn` (warn the user). PodSecurityPolicy (PSP) was **removed in 1.25**. If a course mentions PSP, that's outdated.

```bash
k label ns prod pod-security.kubernetes.io/enforce=restricted \
               pod-security.kubernetes.io/enforce-version=latest \
               pod-security.kubernetes.io/warn=restricted
k -n prod run x --image=nginx       # → Error: violates PodSecurity "restricted:latest": allowPrivilegeEscalation != false, ...
```
A pod that passes `restricted` needs roughly: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`, no hostPath/hostNetwork/privileged.
Existing pods are **not** evicted when you add the label. Only new pods are checked.

> [!warning]
> `enforce` applies to **pods**, so a Deployment is still created, but its **ReplicaSet can't create pods** (READY 0/3, no pods at all) → the error is in `k describe rs`. Same pattern as ResourceQuota. `warn` does show the warning at `apply` time for Deployments too.

---

## 8. Private registries and image security 🟡 MEDIUM

### Analogy
🅿️ **Private car park with a barrier:** public images (Docker Hub) = street parking. A private registry = a gated car park. The pod needs the **gate card** (`imagePullSecrets`) or it can't get in → `ErrImagePull` / `ImagePullBackOff: unauthorized`.

```bash
k create secret docker-registry regcred \
  --docker-server=registry.example.com --docker-username=bob \
  --docker-password='p4ss' --docker-email=bob@example.com
```
```yaml
spec:
  imagePullSecrets:
  - name: regcred              # same namespace as the pod
  containers:
  - name: app
    image: registry.example.com/team/app:1.0
```
Or attach it to the SA so every pod using that SA gets it: `k patch sa default -p '{"imagePullSecrets":[{"name":"regcred"}]}'`.

---

## 9. Encrypting Secrets at rest in etcd 🟡 MEDIUM

> [!example]+ Analogies
> - ✈️ Secrets in etcd are like luggage. By default it goes in the hold **unlocked** (base64 only). Anyone with access to etcd or a backup file can read everything. EncryptionConfiguration = **locking each bag** before it goes in the hold.
> - 🍽 The recipe book (etcd) is in the back office. Encryption at rest = recipes are written in a code only the head chef (API server with the key) can read.

```bash
head -c 32 /dev/urandom | base64          # generate a 32-byte key
```
```yaml
# /etc/kubernetes/enc/enc.yaml   (on the control plane)
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources: ["secrets"]
  providers:
  - aescbc:                    # FIRST provider = used for WRITING new data
      keys:
      - name: key1
        secret: <base64 32-byte key>
  - identity: {}               # still able to READ old unencrypted data
```
Then in `/etc/kubernetes/manifests/kube-apiserver.yaml`:
```yaml
    - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml
  volumeMounts:
  - {name: enc, mountPath: /etc/kubernetes/enc, readOnly: true}
volumes:
- {name: enc, hostPath: {path: /etc/kubernetes/enc, type: DirectoryOrCreate}}
```
> [!warning]
> If `identity: {}` is listed **first**, nothing gets encrypted (the first provider is the one used for writing).

> [!warning]
> The **mount is the step people forget**: the flag points to a path *inside* the API server container. Without the volume → API server crash-loops (`crictl logs`: no such file).

Re-encrypt existing secrets and verify:
```bash
k get secrets -A -o json | k replace -f -        # rewrites all → now encrypted with key1
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/default/mysecret | hexdump -C | head
# encrypted → you see "k8s:enc:aescbc:v1:key1" and garbage; NOT encrypted → you see the plain value
```

---

## 10. Self-check

1. `k get pods` returns `error: You must be logged in to the server (Unauthorized)`. AuthN or AuthZ problem?
2. `Error from server (Forbidden): pods is forbidden: User "jane" cannot list resource "pods"`. AuthN or AuthZ?
3. Which field of a client cert becomes the username? The group?
4. Jane must manage deployments in `dev` and `test` only. Most efficient RBAC design?
5. A user must list **nodes**. Can a Role + RoleBinding do that?
6. You created a RoleBinding but `auth can-i` still says no. Name 3 likely mistakes.
7. What is the `--as` string for SA `bot` in namespace `ci`?
8. Where is a pod's SA token mounted?
9. `capabilities.add: [SYS_TIME]` at pod level. What happens?
10. Pod-level `runAsUser: 1000`, container-level `runAsUser: 2000`. Which wins?
11. You add `--encryption-provider-config` to the API server and it stops starting. Most likely cause?
12. How do you check when the API server certificate expires?
13. How do you create a User object in Kubernetes?
14. Can you change `roleRef` on an existing binding?
15. A Deployment in a PSA-restricted namespace shows 0/3 and `k get po` shows nothing. Where's the error?
16. Which group bypasses RBAC completely?

> [!success]- Answers
> 1. AuthN (401): bad/expired cert or token, or wrong CA in kubeconfig.
> 2. AuthZ (403): authenticated fine, RBAC doesn't allow it.
> 3. CN = username, O = group(s).
> 4. One ClusterRole `deploy-mgr` + one RoleBinding in `dev` and one in `test` (referencing the ClusterRole).
> 5. No. Nodes are cluster-scoped → ClusterRole + ClusterRoleBinding.
> 6. Binding in the wrong namespace; wrong apiGroup (`""` vs `apps`); typo in subject name/kind, or SA namespace missing; resource plural wrong (`deployment` vs `deployments`).
> 7. `system:serviceaccount:ci:bot`.
> 8. `/var/run/secrets/kubernetes.io/serviceaccount/token`.
> 9. Rejected: capabilities only exist at container level.
> 10. Container level: 2000.
> 11. The config file isn't mounted into the API server pod (missing volume/volumeMount), or a YAML/key error in the file.
> 12. `kubeadm certs check-expiration` or `openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate`.
> 13. You can't. Users come from credentials (cert CN, tokens, OIDC).
> 14. No. It's immutable: delete and recreate the binding.
> 15. The ReplicaSet events: `k describe rs -n <ns>`.
> 16. `system:masters` (that's why `super-admin.conf` is break-glass only).

---

## 11. Mini-drills in your kind lab (≈60 min)

```bash
# A. User via CSR (15 min): section 2 end to end for user "jane" (group developers).
#    Give the GROUP developers the built-in "view" ClusterRole in ns dev via a RoleBinding.
#    Prove: k --context=jane -n dev get po (works), k --context=jane -n dev delete po x (forbidden).

# B. SA + RBAC + deployment (10 min): SA "lister" in ns ci, can only list pods, deployment "bot" uses it.
#    Verify with auth can-i AND with the curl/wget-from-inside-the-pod test.

# C. Cert detective (10 min): ./cluster/ssh.sh cp → find the API server cert's SANs and expiry,
#    run kubeadm certs check-expiration, list which flags in kube-apiserver.yaml point to /etc/kubernetes/pki/etcd.

# D. Security context (10 min): pod runs as uid 1000/gid 3000, fsGroup 2000, NET_ADMIN added, no privilege escalation,
#    read-only root FS with an emptyDir on /tmp. Verify with `id` and `touch /tmp/x` (works) and `touch /x` (fails).

# E. Pod Security (5 min): label ns ps with enforce=restricted, try `k run`, read the error,
#    then write a pod that passes. Then create a Deployment there and find the error in `k describe rs`.

# G. Group RBAC (5 min): ClusterRole "pv-reader" + ClusterRoleBinding for group "storage-team";
#    test with k auth can-i list pv --as=x --as-group=storage-team

# F. Encryption at rest (15 min, kind control plane): section 9. Create a secret before and after,
#    compare with etcdctl get | hexdump. Then REMOVE it again cleanly (keep identity first, replace secrets, remove flag).
```

---
← [[03-application-lifecycle]] · [[00 Home|🏠 Home]] · [[05-storage]] →
