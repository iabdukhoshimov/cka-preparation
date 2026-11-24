# Notes: reading order

Read top to bottom once to **understand**, then do the drills and `break.sh`. Every note has analogies (car 🚗, parking 🅿️, football ⚽, restaurant 🍽, cinema 🎬, airport ✈️), annotated YAML, commands, ⚠️ traps, a self-check with hidden answers, and mini-drills for the kind lab.

| # | Note | Exam domain (weight) | Core ideas |
|---|---|---|---|
| 01 | [Core objects](01-core-objects.md) | all | how `kubectl apply` flows, Pod/RS/Deployment/DS/STS/Job/CronJob, Services, labels |
| 02 | [Scheduling, admission, observability](02-scheduling-admission-observability.md) | Workloads 15% / Arch 25% | PriorityClass, static pods, schedulers, admission plugins, webhooks, logs/top |
| 03 | [Application lifecycle](03-application-lifecycle.md) | Workloads 15% | rollouts/rollback, command/args, ConfigMap/Secret, init + sidecar, probes, resources/quota, HPA, Jobs |
| 04 | [Security](04-security.md) | Arch 25% | certs/PKI, CSR users, kubeconfig, **RBAC**, ServiceAccounts, securityContext, Pod Security, encryption at rest |
| 05 | [Storage](05-storage.md) | Storage 10% | volumes, PV/PVC binding rules, access modes, StorageClass, default SC, expansion, StatefulSet PVCs |
| 06 | [Networking](06-networking.md) | Networking 20% | CNI, ports, kube-proxy, **DNS**, **NetworkPolicy** (AND vs OR), Ingress, **Gateway API** |
| 07 | [Cluster maintenance](07-cluster-maintenance.md) | Arch 25% | kubeadm install/upgrade, CRI prep, drain, **etcd backup/restore**, Helm, Kustomize, CRDs |
| 08 | [Troubleshooting and logs](08-troubleshooting-and-logs.md) | Troubleshooting 30% | the method, every pod status, control plane/node failures, logs, JSONPath to files, exam tactics |
| 09 | [Pod placement](09-scheduling-placement.md) | Workloads 15% | taints/tolerations, nodeSelector, node + pod (anti-)affinity, topology spread, nodeName, PDB, Pending decoder |
| 10 | [Helm and Kustomize](10-helm-kustomize.md) | Arch 25% | charts, values precedence, upgrade/rollback, `helm template`, overlays, patches, generators |

## One analogy to tie it all together: the airport ✈️

| Kubernetes | Airport |
|---|---|
| Cluster | the airport |
| Control plane | the control tower + airport management |
| API server | the control tower radio: everyone talks only through it |
| etcd | the flight database |
| Scheduler | gate assignment |
| Controller manager | ground ops making sure reality matches the plan |
| Node | a terminal |
| kubelet | the terminal manager who makes flights actually happen |
| Pod | a flight (one or more planes always together) |
| Deployment | the airline's schedule: "3 flights a day on this route" |
| Service | the airline's check-in desk (fixed place, any free agent serves you) |
| DNS | the departures board |
| Ingress / Gateway | the terminal entrance + signs |
| NetworkPolicy | passport control / security zones |
| RBAC | boarding passes and crew badges |
| PV / PVC | luggage storage / your luggage claim ticket |
| Namespace | separate airline lounges |
| Taints / tolerations | a VIP-only gate: only flights with the right pass may use it |
| Static pod | the airport's own fire brigade: not scheduled by the tower, always there |
| Drain | closing a terminal for repairs and moving the flights elsewhere |
