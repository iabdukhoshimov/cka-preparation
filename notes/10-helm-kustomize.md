# 10: Helm and Kustomize in depth

Domain: **Cluster Architecture, Installation & Configuration (25%)**. Both are in the curriculum and common in exam reports ("install chart X version Y with value Z", "render a chart to a file", "apply this overlay").
The quick version is in `07-cluster-maintenance.md` §6–7. This note goes deeper.

Tags: 🔥 HIGH · 🟡 MEDIUM · 🧊 LOW

---

## The big picture: two ways to customize YAML

| | Helm | Kustomize |
|---|---|---|
| Idea | **templates + values** → YAML | **plain YAML + patches** → YAML |
| 🍽 Restaurant | a meal kit with an order form: tick "spicy", "large", "no onions" | the house recipe, and each branch has a sticky note: "Tashkent branch: more salt" |
| 🚗 Car | buying a car from a configurator (pick colour, engine, wheels) | buying the standard model and taking it to a tuner for changes |
| ⚽ Football | a kit supplier's package: choose your colours and sponsor, they produce the kit | the home kit, with small changes for the away kit |
| 🎬 Cinema | a film franchise template: same story structure, different cast per country | the original film with dubbing/subtitles per country |
| Tool | `helm` CLI (separate binary) | built into kubectl (`-k`) |
| State in cluster | **yes**: releases + revisions (stored as Secrets) | **no**: just applies YAML |
| Rollback | `helm rollback` | re-apply the old files (git) |
| Packaging/sharing | charts in repos/OCI registries | folders (often in git) |

---

## Part A: Helm

### 1. Vocabulary 🔥 HIGH

| Term | Meaning | 🍽 |
|---|---|---|
| **Chart** | a package: templates + default values + metadata | the meal kit box |
| **Values** | the settings that fill the templates | your order form |
| **Release** | one installed instance of a chart, with a name, in a namespace | your actual dinner, order #web |
| **Revision** | each install/upgrade/rollback of a release = +1 | each time you change the order |
| **Repository** | an HTTP index of charts | the meal kit shop |
| **OCI registry** | charts stored like container images (`oci://...`) | the shop's warehouse |

Install the same chart twice with different release names = two independent dinners (`web-a`, `web-b`).

### 2. Chart structure 🟡 MEDIUM
```
mychart/
├── Chart.yaml          # name, version (CHART version), appVersion (APP version), dependencies
├── values.yaml         # default values
├── charts/             # dependency charts (subcharts)
├── templates/          # Go templates → Kubernetes YAML
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── _helpers.tpl    # reusable snippets (files starting with _ are not rendered as objects)
│   └── NOTES.txt       # printed after install
└── crds/               # CRDs, installed before everything else, never upgraded/deleted by Helm
```
```yaml
# templates/deployment.yaml (excerpt)
spec:
  replicas: {{ .Values.replicaCount }}
  template:
    spec:
      containers:
      - name: {{ .Chart.Name }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
```
```yaml
# values.yaml
replicaCount: 1
image:
  repository: nginx
  tag: ""
service:
  type: ClusterIP
  port: 80
```
`.Values` = values, `.Release.Name` / `.Release.Namespace` = release info, `.Chart.Name` / `.Chart.Version` = Chart.yaml.

```bash
helm create mychart          # scaffold a chart
helm lint mychart            # check it
helm template t ./mychart    # render it
```

### 3. Finding charts and versions 🔥 HIGH
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update                                   # refresh indexes (do this after adding!)
helm repo list ; helm repo remove bitnami
helm search repo nginx                             # charts in ADDED repos
helm search repo bitnami/nginx --versions | head   # all versions: CHART VERSION vs APP VERSION
helm search hub nginx                              # Artifact Hub (needs internet)
helm show chart bitnami/nginx                      # Chart.yaml
helm show values bitnami/nginx > values.yaml       # ALL configurable values (edit this copy)
helm show values bitnami/nginx | grep -n -i replica
helm show readme bitnami/nginx | less
helm pull bitnami/nginx --version 15.0.0 --untar   # download the chart folder locally
```
⚠️ `--version` is the **chart** version, not the app version. A task "install nginx 1.25" may mean the appVersion: find the chart version whose APP VERSION is 1.25 with `--versions`.

### 4. Installing and the values precedence 🔥 HIGH
```bash
helm install web bitnami/nginx \
  -n web --create-namespace \
  --version 15.0.0 \
  -f values.yaml -f prod-values.yaml \       # several files: LATER files win
  --set replicaCount=2 \                     # --set wins over -f
  --set service.type=NodePort \              # nested keys with dots
  --set ingress.hosts[0].name=shop.local \   # list items
  --set-string podAnnotations.version=1.0 \  # force a string
  --wait --timeout 5m                        # wait until resources are Ready
helm install web ./mychart                   # local folder
helm install web mychart-0.1.0.tgz           # packaged file
helm install web oci://registry-1.docker.io/bitnamicharts/nginx --version 15.0.0
helm install web bitnami/nginx --dry-run --debug   # show what would be installed
helm install web bitnami/nginx --skip-crds         # 🔥 "install without CRDs"
helm install --generate-name bitnami/nginx         # random release name
```
**Precedence (lowest → highest):** chart's `values.yaml` → `-f` files (in order) → `--set` / `--set-string` / `--set-file` (in order).
⚽ The kit supplier's default kit → your club's design file → the captain's last-minute armband (always wins).

### 5. Inspecting releases 🔥 HIGH
```bash
helm list -n web
helm list -A                       # all namespaces (🔥 "find the release that...")
helm list -A -a                    # include failed/pending/uninstalled-with-history
helm list -A --failed / --pending
helm status web -n web
helm history web -n web
helm get values web -n web         # only values YOU supplied
helm get values web -n web --all   # all computed values
helm get manifest web -n web       # rendered YAML of the current revision
helm get all web -n web
helm get values web -n web --revision 1
k -n web get secret -l owner=helm  # where Helm stores releases: sh.helm.release.v1.web.v1, v2...
```

### 6. Upgrade, rollback, uninstall 🔥 HIGH
```bash
helm upgrade web bitnami/nginx -n web --version 15.1.0 --set replicaCount=3
helm upgrade web bitnami/nginx -n web --reuse-values --set image.tag=1.27   # keep the old values, change one
helm upgrade --install web bitnami/nginx -n web --create-namespace           # idempotent: install or upgrade
helm upgrade web bitnami/nginx -n web --atomic                               # failed upgrade → auto rollback
helm rollback web 1 -n web         # back to revision 1 → creates a NEW revision (e.g. 4)
helm rollback web -n web           # to the previous revision
helm uninstall web -n web          # removes all resources (not CRDs) + the history
helm uninstall web -n web --keep-history
```
⚠️ Without `--reuse-values`, an `upgrade` uses the chart defaults + **only** what you pass now. Values you `--set` at install time are **forgotten**. (🍽 A new order form doesn't keep the boxes you ticked last time.)

⚠️ `rollback` creates a new revision number. It doesn't delete history.

### 7. `helm template`: render without installing 🔥 HIGH
```bash
helm template web bitnami/nginx --version 15.0.0 -n web --set replicaCount=2 > /root/nginx.yaml
helm template web bitnami/nginx --show-only templates/deployment.yaml
helm template web bitnami/nginx --include-crds > all.yaml
k apply -f /root/nginx.yaml          # if the task says "apply the rendered manifest"
```
Exam pattern: "generate the manifest of chart X with value Y into file Z, don't install it". `helm template` doesn't talk to the cluster, so **no release** is created (`helm list` stays empty). That's what they check.

### 8. Dependencies 🧊 LOW
```yaml
# Chart.yaml
dependencies:
- name: redis
  version: 18.x.x
  repository: https://charts.bitnami.com/bitnami
  condition: redis.enabled
```
`helm dependency update ./mychart` → downloads into `charts/`. Subchart values go under their name: `--set redis.auth.enabled=false`.

### 9. Helm exam patterns (summary)
| Task | Commands |
|---|---|
| install chart version X with values in ns Y | `helm repo add/update` → `helm install rel repo/chart -n Y --create-namespace --version X --set ...` |
| find what value controls N | `helm show values repo/chart \| grep -i N` |
| render to a file | `helm template ... > file` |
| no CRDs | `--skip-crds` |
| find a broken/pending release and delete it | `helm list -A -a` → `helm uninstall rel -n ns` |
| upgrade to a newer chart | `helm search repo chart --versions` → `helm upgrade ... --version` |
| roll back | `helm history` → `helm rollback rel N` |
| which values were used | `helm get values rel -n ns` |

### 🔥 Commonly reported task: Argo CD via `helm template`, without CRDs
> "Add the Argo CD Helm repo as `argocd`. Generate a manifest at `/root/argo-helm.yaml` for chart version 7.7.3 in namespace `argocd`, **without installing CRDs**. Then install it as release `argocd`."
```bash
helm repo add argocd https://argoproj.github.io/argo-helm ; helm repo update
helm search repo argocd/argo-cd --versions | head          # is 7.7.3 there?
helm show values argocd/argo-cd --version 7.7.3 | grep -n -A3 -i crds     # find the real key: crds.install
helm template argocd argocd/argo-cd --version 7.7.3 -n argocd --set crds.install=false > /root/argo-helm.yaml
grep -c CustomResourceDefinition /root/argo-helm.yaml      # should be 0
helm install argocd argocd/argo-cd --version 7.7.3 -n argocd --create-namespace --set crds.install=false
```
Two different "no CRDs" switches: `--skip-crds` only skips the chart's `crds/` **folder**. Charts that template their CRDs (like Argo CD) need **their own value** (`crds.install=false`). `helm show values | grep -i crd` tells you which.

### Troubleshooting Helm
| Problem | Check |
|---|---|
| `cannot re-use a name that is still in use` | `helm list -A -a`. Upgrade instead, or uninstall first |
| a value didn't change anything | wrong key path → `helm show values`, then `helm get values rel -n ns` |
| `release: not found` | wrong `-n` namespace (`helm list` without `-A` shows only the current ns) |
| stuck `pending-upgrade` / `pending-install` | `helm rollback` to the last good revision, or uninstall |

Your lab has Helm installed. Note: Bitnami's free images became limited in 2025, so pods may hit ImagePullBackOff. The Helm commands still work for practice. Another chart to practise with: `helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx` or the NGINX Gateway Fabric OCI chart your `up.sh` uses.

---

## Part B: Kustomize

### 10. How it works 🔥 HIGH
- A folder with a `kustomization.yaml` = a **kustomization**.
- A **base** = the common YAML. An **overlay** = a kustomization that uses the base as a resource and changes things.
- Output = plain YAML. `k kustomize dir` prints it, `k apply -k dir` applies it.
- 🍽 base = the house recipe, overlay = the branch's sticky note. 🚗 base = the factory car, overlay = the tuning shop's changes.

```
app/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml      # Deployment "web", image nginx:1.27, 1 replica
│   └── service.yaml
└── overlays/
    ├── dev/
    │   └── kustomization.yaml
    └── prod/
        ├── kustomization.yaml
        ├── resources-patch.yaml
        └── app.env
```

### 11. Every field you'll need 🔥 HIGH
```yaml
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:                       # files, folders (other kustomizations), even URLs
- ../../base
- extra-configmap.yaml

namespace: prod                  # set metadata.namespace on everything (namespace must exist, or include a Namespace resource)
namePrefix: prod-                # web → prod-web (references like a Service selector? no: names in refs ARE updated, e.g. configMapRef)
nameSuffix: -v2

labels:                          # replaces deprecated "commonLabels"
- pairs: {env: prod, team: shop}
  includeSelectors: false        # true = also add to selectors (only for NEW objects; selectors are immutable!)
  includeTemplates: true         # also add to pod templates

commonAnnotations:
  owner: platform-team

images:                          # change images without patching
- name: nginx                    # the image name used in the base
  newName: registry.local/nginx  # optional
  newTag: "1.28"                 # or digest: sha256:...

replicas:
- name: web                      # the ORIGINAL name (before prefix)
  count: 3

configMapGenerator:
- name: web-cfg
  literals: [MODE=prod, LOG=info]
- name: web-files
  files: [nginx.conf]            # key = file name
- name: web-env
  envs: [app.env]                # KEY=VALUE lines
secretGenerator:
- name: db
  literals: [password=s3cret]
  type: Opaque
generatorOptions:
  disableNameSuffixHash: false   # default false → name gets a hash suffix (web-cfg-7f8k2h)

patches:                         # the modern field (patchesStrategicMerge / patchesJson6902 are deprecated)
- path: resources-patch.yaml     # strategic merge patch file
- target:                        # JSON6902 patch, inline, applied to matching objects
    kind: Deployment
    name: web
  patch: |-
    - op: replace
      path: /spec/template/spec/containers/0/image
      value: nginx:1.28
    - op: add
      path: /spec/template/spec/containers/0/env
      value:
      - {name: LOG, value: info}
- target:
    kind: Deployment
    labelSelector: tier=frontend  # patch every Deployment with this label
  patch: |-
    - op: add
      path: /spec/template/metadata/annotations
      value: {prometheus.io/scrape: "true"}
```

### 12. Strategic merge patches 🔥 HIGH
A **partial object** with enough identity (apiVersion, kind, name) to find the target. Lists of containers are merged **by `name`**.
```yaml
# resources-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web                     # original name (before the prefix)
spec:
  template:
    spec:
      containers:
      - name: nginx             # matched by name, only the fields below change
        resources:
          limits: {memory: 256Mi}
      - name: sidecar           # new name → container is ADDED
        image: busybox:1.36
        command: ["sh", "-c", "sleep 1d"]
```
Delete something with a patch:
```yaml
spec:
  template:
    spec:
      containers:
      - name: debug
        $patch: delete          # remove this container from the base
```
| Patch type | Good for | 🚗 |
|---|---|---|
| strategic merge (YAML file) | changing/adding fields, containers by name | bolt on parts that fit the car |
| JSON6902 (`op/path/value`) | exact operations: replace a list item by index, remove a field | precise surgery: "replace the part at position 0" |

JSON6902 ops: `add`, `remove`, `replace`, `move`, `copy`, `test`. A path to a list index: `/spec/template/spec/containers/0/image`. Append to a list: `/.../containers/-`.

### 13. Why the generator hash matters 🟡 MEDIUM
`configMapGenerator` names the CM `web-cfg-<hash>` and **rewrites every reference** to it in the Deployments. Change a literal → new hash → new name → the pod template changes → **automatic rolling update**. (Compare with `03-application-lifecycle.md` §3: a normal CM change does NOT restart pods.)
🍽 The new menu gets a new version number, so every waiter is forced to pick up the new copy.

### 14. Commands and checks 🔥 HIGH
```bash
k kustomize overlays/prod                   # ALWAYS render first and read it
k kustomize overlays/prod | grep -E 'name:|image:|replicas:|namespace:'
k apply -k overlays/prod
k diff -k overlays/prod                     # what would change
k delete -k overlays/prod
k get all -n prod -l env=prod
kustomize build overlays/prod               # standalone binary (same output; your lab has it)
```

### 15. Kustomize traps 🔥 HIGH
- `resources:` paths are **relative to the kustomization.yaml** (`../../base`).
- `replicas:` / `images:` / patches use the **original** name, before `namePrefix`.
- `namespace:` doesn't create the namespace. Create it first or add a `Namespace` resource.
- The file must be named `kustomization.yaml` (or `.yml` / `Kustomization`).
- `includeSelectors: true` on already-running Deployments → apply fails (`field is immutable`).
- `k apply -f dir/` ignores `kustomization.yaml`. You need **`-k`**.
- Older tutorials use `bases:`, `commonLabels:`, `patchesStrategicMerge:`. They're deprecated (they still work in many versions, with warnings). Prefer `resources:`, `labels:`, `patches:`.

### 16. Helm + Kustomize together 🧊 LOW
`helm template ... > base/chart.yaml`, then patch it with a Kustomize overlay. (Kustomize also has a `helmCharts:` field, which needs `--enable-helm`. Rare.)

---

## 17. Self-check

1. `-f a.yaml -f b.yaml --set x=1`: both files set `x` too. Which value wins?
2. You installed with `--set replicaCount=3`, then `helm upgrade web repo/chart --set image.tag=2`. Replicas now?
3. Difference between `helm template` and `helm install --dry-run`?
4. `helm rollback web 2` when the current revision is 5. New revision number?
5. Chart version vs app version?
6. A release is stuck in `pending-install` and `helm list` shows nothing. How do you find it?
7. Where does Helm store release history?
8. Kustomize: base Deployment is `web`, overlay has `namePrefix: prod-`. Which name goes into `replicas:`?
9. You change a literal in a `configMapGenerator`. What happens to the pods after `k apply -k`?
10. Strategic merge vs JSON6902: when do you use which?
11. `k apply -f overlays/prod/` doesn't apply the overlay. Why?
12. How do you remove a container defined in the base from an overlay?
13. `--skip-crds` was used but CRDs still appear in the rendered output. Why?

<details><summary>Answers</summary>

1. `--set x=1` (`--set` beats `-f`, and among files the later one wins).
2. Back to the chart default (e.g. 1), because install-time values aren't kept without `--reuse-values`.
3. `template` renders locally with no cluster or release. `install --dry-run` talks to the cluster (validates, simulates), still no release.
4. 6.
5. Chart version = the package version (`--version`). App version = the version of the software inside (e.g. nginx 1.27).
6. `helm list -A -a` (or `--pending`), then `helm uninstall <rel> -n <ns>` or roll back.
7. Secrets in the release namespace: `sh.helm.release.v1.<name>.v<revision>`.
8. `web` (the original name).
9. New CM name (hash) → the Deployment template references the new name → rolling update.
10. Strategic merge: add/change fields, containers by name, readable. JSON6902: precise ops (by index, removing, replacing a whole field).
11. `-f` ignores kustomization.yaml. Use `k apply -k overlays/prod`.
12. A strategic merge patch with `- name: <container>` + `$patch: delete` (or JSON6902 `op: remove` on its index).
13. The chart templates its CRDs instead of keeping them in `crds/`. Disable them with the chart's own value (e.g. `--set crds.install=false`).
</details>

---

## 18. Mini-drills in your kind lab (≈60 min)

```bash
# A. Helm basics (15 min): drill 1.4 in drills/DRILLS.md, plus: helm get values, helm get manifest | grep replicas,
#    k get secret -n helm-lab -l owner=helm.

# B. Values precedence (10 min): helm show values > v1.yaml; make v2.yaml; install with -f v1 -f v2 --set,
#    predict replicaCount, check with helm get values --all.

# C. The reuse-values trap (5 min): install with --set replicaCount=3, upgrade with only --set image.tag=..., count pods.
#    Redo with --reuse-values.

# D. helm template (5 min): render to /root/out.yaml with replicaCount=2, check helm list -A is still empty, then k apply -f.

# E. helm create (10 min): helm create mychart → change values.yaml → helm lint → helm install → helm upgrade → rollback.

# F. Kustomize overlay (15 min): base (deploy + svc) + overlays dev/prod with namespace, prefix, labels, images,
#    replicas, configMapGenerator and one strategic merge patch adding resources. k kustomize, k apply -k, k diff -k.
#    Then change the generator literal and watch the pods roll (k get po -w).
```
