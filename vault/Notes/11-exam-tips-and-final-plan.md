---
tags:
  - cka/exam
---

← [[10-helm-kustomize]] · [[00 Home|🏠 Home]]

# 11: Exam tips, speed toolkit, docs map, killer.sh plan, exam-day checklist

**Exam: Saturday, Nov 28.** killer.sh on Nov 26 and 27.

Tags: 🔥 HIGH · 🟡 MEDIUM · 🧊 LOW

---

## 1. The exam format (know what you're walking into)
- **2 hours**, about **15–20 hands-on tasks** in real clusters. **Pass = 66%.** Each task shows its weight (%).
- Remote proctored by **PSI** (the PSI Secure Browser). You work in a **remote Linux desktop** with a terminal and a browser.
- **One browser tab** for the allowed docs: kubernetes.io/docs and kubernetes.io/blog (and the other sites the Linux Foundation lists for CKA. Check their current "allowed resources" page before the exam).
- Every task starts with a line like `kubectl config use-context k8s-c1` **or** tells you to `ssh <host>`. **Different tasks = different clusters/hosts.**
- Partial credit exists: a task is scored by several checks. **Do what you can, even if you can't finish it.**
- Copy/paste inside the remote desktop: in the terminal `Ctrl+Shift+C` / `Ctrl+Shift+V`. Or select with the mouse and middle-click.
- `k` alias and bash completion are usually preconfigured. Check in the first minute.

### Analogy
⚽ It's a **cup final with 17 penalties**. Each penalty has a different value (%). You don't need all of them: **66% wins**. Missing one doesn't lose the match; **spending 20 minutes on one penalty does.**

---

## 2. The first 2 minutes of the exam
```bash
alias k=kubectl                          # probably already there: type "k get no" to check
complete -o default -F __start_kubectl k # completion for k (if it's missing)
export do="--dry-run=client -o yaml"
export now="--force --grace-period=0"
cat >> ~/.vimrc <<'EOF'
set expandtab tabstop=2 shiftwidth=2 softtabstop=2 autoindent number
EOF
```
(When you `ssh` to another node, these don't follow you. That's fine; on nodes you mostly use vi, systemctl and crictl.)

---

## 3. The workflow for EVERY task 🔥
1. **Read the whole task.** Note: the **context**, the **namespace**, the exact **names**, the **output file paths**, the **container names**.
2. **Run the `use-context` line** (copy it from the task). Every single time.
3. Generate YAML imperatively (`$do > x.yaml`) → edit it → `k apply -f x.yaml`.
4. **Verify** in the way the grader will: `k get`, `describe`, `curl`, `auth can-i`, `cat` the output file.
5. Doubtful or too long? **Flag it and move on** (the exam UI has a flag button). Write the task number on the notepad.
6. If you `ssh`'d into a node → **`exit`** back to the base terminal before the next task.

### Time strategy
- Average budget = **~7 min per task**.
- **Pass 1 (≈80 min):** do everything that's quick (RBAC, sc, pvc, svc, netpol, hpa, helm, logs-to-file). Flag the long ones.
- **Pass 2 (≈30 min):** the flagged tasks (etcd restore, kubeadm upgrade, a broken control plane, a big Gateway migration).
- **Last 10 min:** re-check the output files and namespaces of the high-weight tasks.
- A troubleshooting task worth 7–8% is worth 10 minutes. A 2% task isn't worth 10.

---

## 4. Speed toolkit 🔥

### Generate, don't type
```bash
k run p --image=nginx:1.27 --labels=app=web --port=80 $do > p.yaml
k create deploy web --image=nginx:1.27 --replicas=3 $do > d.yaml
k create job j --image=busybox $do -- sh -c 'echo hi'
k create cronjob c --image=busybox --schedule="*/5 * * * *" $do -- date
k expose deploy web --port=80 --target-port=8080 --type=NodePort $do
k create cm c --from-literal=K=V $do ; k create secret generic s --from-literal=p=x $do
k create sa ci -n build
k create role r --verb=get,list --resource=pods -n dev
k create rolebinding rb --role=r --serviceaccount=dev:ci -n dev
k create clusterrole cr --verb=get,list --resource=nodes
k create clusterrolebinding crb --clusterrole=cr --user=jane
k create ingress i --class=nginx --rule="a.com/x*=svc:80" $do
k create quota q --hard=pods=5 -n x ; k create pdb p --selector=app=web --min-available=2
k create priorityclass high --value=1000
k create token ci -n build
k autoscale deploy web --min=1 --max=5 --cpu-percent=50 $do
```
No generator → copy from the docs: PV, PVC, StorageClass, NetworkPolicy, DaemonSet (convert a deployment), StatefulSet, Gateway/HTTPRoute, LimitRange, CSR.

### Change things fast
```bash
k set image deploy/web nginx=nginx:1.28
k set resources deploy web -c nginx --requests=cpu=100m,memory=64Mi --limits=memory=128Mi
k set env deploy/web MODE=prod ; k set env deploy/web --from=configmap/app-cfg
k set serviceaccount deploy/web ci
k scale deploy web --replicas=5
k label po x tier=web --overwrite ; k annotate deploy web note=hi
k patch deploy web -p '{"spec":{"template":{"spec":{"priorityClassName":"high"}}}}'
k edit deploy web            # if the edit is rejected, kubectl saves your copy to /tmp/kubectl-edit-xxxx.yaml
k replace --force -f /tmp/kubectl-edit-xxxx.yaml    # for fields that can't be changed on a running pod
k get po x -o yaml > x.yaml ; vi x.yaml ; k replace --force -f x.yaml    # same idea
k delete po x $now
```

### Find things fast
```bash
k explain deploy.spec.strategy.rollingUpdate      # field docs without the browser
k explain pod.spec.containers.securityContext --recursive | less
k api-resources | grep -i <word>                  # kind, short name, group
k get po -A -o wide --show-labels
k get po -l app=web -n x
k get po --field-selector status.phase!=Running -A
k get po -A --sort-by=.metadata.creationTimestamp
k get po -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName,IMG:.spec.containers[*].image
k get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'
k get po x -o jsonpath='{.spec.containers[0].image}'
k get secret s -o jsonpath='{.data.password}' | base64 -d
k get po -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.podIP}{"\n"}{end}'
```

### vi survival kit (the exam's editor)
| Keys | Action |
|---|---|
| `i` / `Esc` | insert mode / back to normal mode |
| `:wq` / `:q!` | save+quit / quit without saving |
| `dd` / `5dd` / `yy` / `p` | delete line(s) / copy line / paste |
| `u` / `Ctrl+r` | undo / redo |
| `/word` then `n` | search |
| `:%s/old/new/g` | replace everywhere |
| `Shift+V`, select with `j`, then `>` or `<` | indent / outdent a block (fixes pasted YAML) |
| `gg` / `G` / `:42` | top / bottom / line 42 |
| `:set paste` | before pasting, if the auto-indent messes up the YAML |
| `ciw` / `cw` | change a word |

YAML rules: **spaces only, never tabs**. List items `-` are aligned under their parent key or indented two more, but **be consistent**.

---

## 5. Docs map: what to search on kubernetes.io 🔥
Practise finding each of these in **under 30 seconds** (use the docs search box):

| You need | Search for |
|---|---|
| PV + PVC + Pod YAML | "Configure a Pod to Use a PersistentVolume for Storage" |
| StorageClass fields | "Storage Classes" |
| NetworkPolicy examples | "Network Policies" (the default deny/allow section) |
| Ingress YAML | "Ingress" |
| Gateway / HTTPRoute | "Gateway API" |
| node affinity | "Assign Pods to Nodes using Node Affinity" |
| taints | "Taints and Tolerations" |
| topology spread | "Pod Topology Spread Constraints" |
| HPA + behavior | "Horizontal Pod Autoscaling" / "HorizontalPodAutoscaler Walkthrough" |
| sidecar | "Sidecar Containers" |
| init containers | "Init Containers" |
| probes | "Configure Liveness, Readiness and Startup Probes" |
| securityContext | "Configure a Security Context for a Pod or Container" |
| PSA labels | "Enforce Pod Security Standards with Namespace Labels" |
| RBAC | "Using RBAC Authorization" |
| CSR user | "Certificates and Certificate Signing Requests" |
| ServiceAccounts | "Configure Service Accounts for Pods" |
| etcd backup | "Operating etcd clusters for Kubernetes" |
| kubeadm upgrade | "Upgrading kubeadm clusters" |
| kubeadm install | "Installing kubeadm" / "Creating a cluster with kubeadm" |
| cert renewal | "Certificate Management with kubeadm" |
| CoreDNS | "Customizing DNS Service" / "Debugging DNS Resolution" |
| DNS names | "DNS for Services and Pods" |
| static pods | "Create static Pods" |
| PriorityClass | "Pod Priority and Preemption" |
| LimitRange / quota | "Limit Ranges" / "Resource Quotas" |
| PDB | "Specifying a Disruption Budget" |
| drain | "Safely Drain a Node" |
| CRD | "Extend the Kubernetes API with CustomResourceDefinitions" |
| Kustomize | "Declarative Management of Kubernetes Objects Using Kustomize" |
| kubectl cheat sheet | "kubectl Quick Reference" |
| jsonpath | "JSONPath Support" |
| encryption at rest | "Encrypting Confidential Data at Rest" |
| debug | "Debug Running Pods" |
| sysctls / container runtimes | "Container Runtimes" (the IPv4 forwarding section) |

---

## 6. The most common ways people LOSE points 🔥
1. Didn't run `use-context` → solved the task in the wrong cluster. **Zero points.**
2. Wrong namespace (forgot `-n`, or `metadata.namespace`).
3. A typo in a name: `web-deploy` vs `web-deployment`. **Copy names from the question** (Ctrl+Shift+C).
4. Output file: wrong path, or extra/missing content. Run `cat` on the file.
5. Edited the Deployment but the task asked for the **pod** (or the reverse).
6. Static pod / manifest edits on the **wrong node**, or forgot to `exit` the ssh session.
7. Never verified: the Service has no endpoints, the PVC is Pending, the pod is CrashLooping.
8. Spent 25 minutes on one 4% task.
9. A deny-all NetworkPolicy without allowing DNS.
10. etcd restore: changed the data dir in the wrong place, or didn't wait for the API to come back.
11. Deleted something the task didn't ask you to delete.
12. Forgot to `systemctl enable` (if the task says "persist" or "after reboot") or to persist sysctls in `/etc/sysctl.d/`.

---

## 7. killer.sh plan (Nov 26–27) 🔥

Facts: you get **2 sessions**. Each runs **36 hours** from activation, and both sessions have the **same questions**. killer.sh is **harder and longer** than the real exam, so **a score of 50–60% there is a good sign**.

### Nov 25 (Wednesday): preparation day
- Read notes **08 (troubleshooting)**, **07 (etcd/kubeadm)**, **06 §5 (NetworkPolicy)**, **06 §7 (Gateway API)** again.
- Lab: `../troubleshoot/break.sh 1–10`, each under 5 min.
- KodeKloud: one full mock exam under exam conditions, then fill in your mistakes log.
- Killercoda: a kubeadm upgrade + an etcd restore (because kind can't do kubeadm).

### Nov 26 (Thursday): killer.sh session 1
| Time | What |
|---|---|
| 09:00–11:00 | **Activate session 1. Exam conditions:** 2 h timer, one docs tab, no notes, no help |
| 11:00–11:30 | Break. Write down your score and which questions you skipped |
| 11:30–15:00 | Read **every** solution, including the ones you got right (you'll learn faster ways) |
| 15:00–18:00 | **Redo every wrong/skipped question** inside the session (it's still active) without looking |
| 18:00–20:00 | Add the mistakes to the log. Read the related notes file for each weak topic |
| 21:00 | Stop. Sleep |

### Nov 27 (Friday): killer.sh session 2, then rest
| Time | What |
|---|---|
| 09:00–10:30 | **Activate session 2** (same questions). Speed run: target **under 90 minutes, 85%+** |
| 10:30–13:00 | Redo only what was still slow |
| 14:00–16:00 | Light: this file (§3–§6) + your mistakes log + the self-checks at the end of each notes file |
| 16:00 | **PSI system check**, install/test the PSI Secure Browser, webcam + mic, ID ready |
| 17:00 | **Stop studying.** Walk, eat well, no screens late. Sleep 8 h |

---

## 8. Exam-day checklist (Nov 28)
**Night before / morning:**
- [ ] Government ID with a photo, name matching your exam registration exactly
- [ ] Clean desk (nothing except your computer, and maybe a clear glass of water if it's allowed. Check the current rules)
- [ ] Quiet, closed room, alone. No second monitor (disconnect it), no phone within reach
- [ ] Laptop **plugged in**, stable internet (cable if possible). Close all other apps, disable notifications
- [ ] Webcam can be moved/shown around the room for the room scan
- [ ] Light breakfast, use the toilet before starting
- [ ] Be at your desk and launch check-in **30 minutes early**

**During:**
- [ ] First 2 min: aliases + vimrc (§2)
- [ ] `use-context` on every task
- [ ] Quick tasks first, flag the long ones
- [ ] Stuck for over 7 min → flag → next
- [ ] Stay calm if something is broken: **it's broken on purpose, and fixing it is the task**
- [ ] Last 10 min: re-check the output files and namespaces

### Mindset
🎬 A film director doesn't redo scene 1 forever. They shoot what's ready, move on, and come back for the difficult scenes.
⚽ "Victory belongs to whoever keeps playing until the final whistle." If a task goes badly, the next one is a new penalty. **Reset after every task.**

---

## 9. Final 20-question rapid fire (answer out loud in under 10 s each)
1. Port for etcd clients? → 2379
2. Where are the static pod manifests? → `/etc/kubernetes/manifests` (check `staticPodPath`)
3. How do you see a crashed container's logs? → `k logs <pod> --previous`
4. Empty Service endpoints → ? → selector ≠ labels, or the pods aren't Ready
5. RBAC group for deployments → `apps`
6. A user is identified by which field of their cert? → CN (groups = O)
7. Which flag makes `etcdutl` restore to a new folder? → `--data-dir`
8. One dash vs two dashes in a netpol `from`? → AND vs OR
9. Default StorageClass annotation? → `storageclass.kubernetes.io/is-default-class: "true"`
10. Released PV → Available? → patch `claimRef` to null
11. HPA `<unknown>` → ? → no requests, or metrics-server is down
12. Pending, no events → ? → the scheduler
13. Deployment with 0 pods, quota in the namespace → where to look? → `k describe rs`
14. Upgrade order for a worker? → kubeadm → `upgrade node` → drain → kubelet/kubectl → restart → uncordon
15. CNI with NetworkPolicy support? → Calico / Cilium (not Flannel)
16. The Gateway API object that holds the TLS cert? → Gateway listener `certificateRefs`
17. Native sidecar? → initContainer with `restartPolicy: Always`
18. Persist sysctls where? → `/etc/sysctl.d/*.conf` + `sysctl --system`
19. Render a Helm chart without installing it? → `helm template`
20. Can't change a pod field → ? → `k replace --force -f`

---
← [[10-helm-kustomize]] · [[00 Home|🏠 Home]]
