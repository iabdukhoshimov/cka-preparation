# 10-day CKA sprint: Nov 15 → exam Nov 25 (k8s v1.37)

> **UPDATE (Nov 24): the exam moved to Sat Nov 28.** The remaining days:
> Nov 24–25 topic notes + labs (`notes/README.md`) · Nov 26 killer.sh #1 · Nov 27 killer.sh #2 + rest · Nov 28 exam.
> Exam tips, speed toolkit, docs map & checklist: `notes/11-exam-tips-and-final-plan.md`.

The level is intermediate: you've done KodeKloud Pro and Killercoda once each. The goal now is **speed, accuracy, and zero panic**, not learning new things.
Pass mark is 66%. Aim for **≥ 85% on KodeKloud mocks** and **≥ 60% on killer.sh**, which is harder than the real exam.

## Rules for the next 10 days
1. **Everything is timed.** Start a timer for every task. If a task takes more than 6–7 min, move on and flag it, the same as in the exam.
2. **Plain kubectl + kubernetes.io docs only.** No k9s, no Google, no ChatGPT while solving.
3. **Mistakes log** (bottom of this file). Write down every wrong or slow answer: what the task was, why you got it wrong, and the fix. Re-do the whole log every evening.
4. **Verify every answer** with `k get`, `k describe`, `curl`, `auth can-i`, or the logs. Unverified answers lose points.
5. Get **7+ hours of sleep.** 12 h/day means about 10.5 h of focused work plus breaks. Burning out on day 6 is worse than a shorter day.

## Daily template (about 12 h)

| Time | Block |
|---|---|
| 07:30–08:00 | Warm-up: type bashrc/vimrc from memory, 10 imperative one-liners (pod/deploy/svc/role/rolebinding/cm/secret/job/cronjob) |
| 08:00–10:00 | **Block A:** topic of the day, timed drills (`drills/DRILLS.md` + references) |
| 10:15–12:15 | **Block B:** KodeKloud Pro labs / mock for the same topic |
| 12:15–13:00 | Lunch (away from the screen) |
| 13:00–15:00 | **Block C:** troubleshooting reps (`troubleshoot/break.sh`, KodeKloud troubleshooting labs) |
| 15:15–17:15 | **Block D:** Killercoda CKA scenarios / mock exam |
| 17:15–18:15 | Break, food, walk |
| 18:15–19:45 | **Block E:** review everything you got wrong today; redo it without notes |
| 19:45–20:30 | Mistakes log re-do + docs navigation (find a page in under 30 s) |

---

## Day 1: Sun Nov 15, baseline
- [ ] `./cluster/up.sh --gateway`, shell setup from memory
- [ ] **KodeKloud CKA Mock Exam 1**: strict 2 h, no notes. Score: ____
- [ ] Rank the 5 domains from weakest to strongest based on the score. That ranking changes how much time days 2–5 get.
- [ ] `troubleshoot/break.sh 1..10` once, untimed. Note which ones you couldn't fix.

## Day 2: Mon Nov 16, Troubleshooting (30%, the biggest domain)
- [ ] Control plane: broken static pod manifests (`/etc/kubernetes/manifests`), wrong flags, wrong cert paths, etcd endpoint
- [ ] Node: kubelet down or misconfigured (`systemctl status kubelet`, `journalctl -u kubelet`, `/var/lib/kubelet/config.yaml`), containerd, `crictl ps/logs`
- [ ] Apps: CrashLoopBackOff, ImagePull errors, bad probes, wrong selector/targetPort, missing endpoints, DNS
- [ ] `k top`, `k logs -p`, `k get events --sort-by=.lastTimestamp`
- [ ] `break.sh 1..10` **timed, each under 5 min**
- [ ] `references/CKA-Exercises/troubleshooting.md`, `references/CKA-practice-exercises/troubleshooting.md`
- [ ] Killercoda: all troubleshooting scenarios

## Day 3: Tue Nov 17, Cluster Architecture (25%)
- [ ] RBAC: Role/ClusterRole/bindings/ServiceAccount, `k auth can-i --as=system:serviceaccount:ns:sa`
- [ ] **etcd backup + restore blind, 3 times** (snapshot save, restore to a new data-dir, edit the etcd manifest)
- [ ] **kubeadm upgrade (cp + worker) and join** on Killercoda, because VT-x is off here. Do it twice.
- [ ] Certs: `kubeadm certs check-expiration` / `renew`
- [ ] Helm: repo add, install with `--set`/values, upgrade, `helm template`, list across namespaces
- [ ] Kustomize: `k apply -k`, patches
- [ ] CRDs/operators: `k get crd`, `k explain <crd>.spec`, install an operator from a manifest
- [ ] Extension interfaces: install a CNI from its manifest (Calico/Flannel), CRI prep (`dpkg -i` a .deb, sysctl `net.ipv4.ip_forward` / bridge settings persisted in `/etc/sysctl.d/`)

## Day 4: Wed Nov 18, Services & Networking (20%)
- [ ] Services: ClusterIP/NodePort/headless, `k expose`, endpoints/EndpointSlices
- [ ] DNS: `svc.ns.svc.cluster.local`, pod DNS, CoreDNS ConfigMap edits
- [ ] **NetworkPolicy**: ingress + egress, namespaceSelector vs podSelector (AND vs OR), allow DNS egress, choosing the *least permissive* policy that works
- [ ] Ingress (pathType, rewrite annotation, ingressClassName)
- [ ] **Gateway API**: Gateway, HTTPRoute (path/header matches, weights), migrating an Ingress to an HTTPRoute
- [ ] Drills 4.1–4.5, KodeKloud networking labs

## Day 5: Thu Nov 19, Workloads & Scheduling (15%) + Storage (10%)
- [ ] Deployments: rollout/undo/history, scale, `set image`, env from cm/secret
- [ ] Native sidecar (`initContainers` with `restartPolicy: Always`), shared emptyDir
- [ ] HPA (`k autoscale`, plus `behavior` in YAML), resources, LimitRange, ResourceQuota
- [ ] Scheduling: nodeSelector, affinity, taints/tolerations, **PriorityClass**, static pods, DaemonSet
- [ ] Storage: PV/PVC/StorageClass, accessModes, reclaimPolicy, `volumeBindingMode: WaitForFirstConsumer`, default SC annotation, PVC expansion
- [ ] Evening: **KodeKloud Mock Exam 2** (2 h, strict). Score: ____

## Day 6: Fri Nov 20, killer.sh #1
- [ ] Morning: killer.sh session #1, strict 2 h. Score: ____ (60%+ is a good result)
- [ ] Afternoon/evening: read **every** solution, even the ones you got right. Redo every question inside the 36 h window.
- [ ] Add all misses to the mistakes log

## Day 7: Sat Nov 21, weak-area repair
- [ ] Spend the whole day on your 2 weakest domains (mistakes log + killer.sh misses)
- [ ] KodeKloud: Lightning Labs + the Ultimate CKA Mock Exam Series (as many as fit)
- [ ] etcd backup/restore + kubeadm upgrade one more time each

## Day 8: Sun Nov 22, mock marathon
- [ ] **KodeKloud Mock Exam 3** (2 h). Score: ____
- [ ] Ultimate mock series: one more full set (2 h). Score: ____
- [ ] `break.sh 1..10`, round 2, **every one under 4 min**
- [ ] Evening: review + mistakes log

## Day 9: Mon Nov 23, killer.sh #2
- [ ] killer.sh session #2. It's usually the same question set, so treat it as a **speed run**: target finishing in under 90 min. Time: ____
- [ ] Redo anything still slow
- [ ] Read `references/cka-certification-guide/EXAM_DAY_GUIDE.md` + `EXAM_TIPS.md`

## Day 10: Tue Nov 24, light day (no new material)
- [ ] Mistakes log re-do only, plus 1 h of imperative-command speed reps
- [ ] **PSI system check** (browser, webcam, mic), ID ready, clean desk, quiet room booked
- [ ] Stop studying by 18:00. Sleep early.

## Exam day: Wed Nov 25
- Light breakfast, be ready 30 min early, have the ID next to you
- First 2 min: `alias k=kubectl` (usually already set), `export do="--dry-run=client -o yaml"`, vim `set ts=2 sw=2 et`
- **Run the `kubectl config use-context` line on every question**
- First pass: do the easy/quick tasks and flag long ones. Second pass: the flagged ones. Use the last 10 min for verification.
- After `ssh` into a node, always `exit` back before the next task
- Keep the weight % in mind: a 4% troubleshooting task is worth more time than a 2% one

---

## Score tracker

| Date | Test | Score | Time used | Weakest area |
|---|---|---|---|---|
| Nov 15 | KK Mock 1 | | | |
| Nov 19 | KK Mock 2 | | | |
| Nov 20 | killer.sh #1 | | | |
| Nov 22 | KK Mock 3 | | | |
| Nov 22 | Ultimate mock | | | |
| Nov 23 | killer.sh #2 | | | |

## Mistakes log

| # | Task | What I did wrong / why slow | Correct approach / docs page | Re-done ✔ |
|---|---|---|---|---|
| 1 | | | | |
