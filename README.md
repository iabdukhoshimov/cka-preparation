# CKA prep lab (Kubernetes v1.37)

A local, exam-like practice environment: a 3-node kind cluster with Calico and metrics-server (and Gateway API on request), break/fix troubleshooting scenarios, domain drills, and a study plan.

## Quick start

```bash
bash setup/install.sh        # sudo: docker, kubectl, kind, helm, kustomize, etcdctl, k9s, vim...
newgrp docker                # or log out/in once
source ~/.bashrc             # gives you: k, completion, $do, $now, kn <ns>
./cluster/up.sh              # 1 control plane + 2 workers, k8s v1.37.0
./cluster/up.sh --gateway    # same + Gateway API + NGINX Gateway Fabric
./cluster/ssh.sh cp|w1|w2    # "ssh" into a node (crictl, kubelet, /etc/kubernetes)
./cluster/down.sh            # destroy (recreate in ~2 min, so break things freely)
```

## Layout

| Path | What |
|---|---|
| `STUDY_PLAN.md` | 4-week plan with checkboxes, mapped to the 5 exam domains |
| `drills/DRILLS.md` | ~25 timed tasks per domain with hidden solutions |
| `troubleshoot/` | `break.sh <n>` breaks the cluster, `check.sh <n>` verifies your fix, `SOLUTIONS.md` |
| `setup/` | installer, exam-style bashrc + vimrc |
| `cluster/` | kind config and lifecycle scripts |
| `references/` | git submodules: [techiescamp/cka-certification-guide](https://github.com/techiescamp/cka-certification-guide), [chadmcrowell/CKA-Exercises](https://github.com/chadmcrowell/CKA-Exercises), [alijahnas/CKA-practice-exercises](https://github.com/alijahnas/CKA-practice-exercises) |

Update the references with `git submodule update --remote`.

## Exam domains (CKA v1.37)

| Domain | Weight |
|---|---|
| Troubleshooting | 30% |
| Cluster Architecture, Installation & Configuration | 25% |
| Services & Networking | 20% |
| Workloads & Scheduling | 15% |
| Storage | 10% |

## What kind can't simulate

- **kubeadm install / upgrade / join** needs real VMs. VT-x is currently **disabled in BIOS** on this machine (i5-12400F supports it). Enable *Intel Virtualization Technology* in BIOS, and then you can run 2–3 VMs with libvirt for kubeadm practice. Otherwise, use killer.sh / Killercoda for those tasks.
- Nodes use `docker exec` instead of `ssh`, and `apt` isn't how components are installed.

## Other resources

- **killer.sh**: 2 free sessions come with the exam purchase. The closest thing to the real exam
- **Killercoda CKA**: https://killercoda.com/killer-shell-cka (free browser labs, including kubeadm)
- **Docs** (the only site allowed in the exam): https://kubernetes.io/docs · learn its search and the kubectl cheat sheet
- **Curriculum**: https://github.com/cncf/curriculum
- `k9s`, `kubectx`, `stern` are installed for comfort, but **they're not in the exam**. Do drills with plain `kubectl`.
