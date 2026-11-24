---
tags:
  - cka/networking
---

← [[05-storage]] · [[00 Home|🏠 Home]] · [[07-cluster-maintenance]] →

# 06: Networking: pod network, CNI, Services, DNS, NetworkPolicy, Ingress, Gateway API

Domain: **Services & Networking (20%)**, and DNS/Service bugs are a big part of **Troubleshooting (30%)**.
Service basics (types, the three ports) are in [[01-core-objects]] §7. This note covers everything around them.

Tags: 🔥 HIGH · 🟡 MEDIUM · 🧊 LOW

---

## The big picture in one story: the airport ✈️ and the city 🏙

```
 Internet / your laptop
      │
      ▼
 Gateway / Ingress  ✈️ the airport terminal: one entrance, signs route you by destination (host/path)
      │
      ▼
 Service            📞 the airline's hotline number: same number forever, rings whichever agent is free
      │  (kube-proxy rules on every node)
      ▼
 Pod IPs            🧑‍✈️ the individual agents: they come and go, numbers change
      ▲
      │ CNI (Calico) gives every pod an IP and connects nodes   🛣 the road network between buildings
 CoreDNS            📖 the phone book: "web.prod" → 10.96.12.34
 NetworkPolicy      🛂 passport control / nightclub bouncer: who may talk to whom
```

| Concept | 🚗 City / car | ✈️ Airport | ⚽ Football | 🍽 Restaurant |
|---|---|---|---|---|
| Pod IP | a car's current parking spot: changes every time | a passenger's seat number on today's flight | a player's position on the pitch today | which table the waiter is at right now |
| Service ClusterIP | the company's street address: never changes | the airline's check-in desk | the club's official address | the restaurant's phone number |
| Endpoints / EndpointSlice | the list of employees currently in the building | the agents currently at the desk | today's starting eleven | the waiters on shift now |
| kube-proxy | the receptionist who forwards calls to a free employee | the queue system that sends you to a free agent | the coach passing instructions to whoever is on the pitch | the host who seats you at a free waiter's table |
| CNI | the road builders: connect every house to every street | the airport's internal shuttle/tunnels | the pitch markings everyone plays on | the corridors between kitchen and tables |
| CoreDNS | the phone book / GPS address lookup | the departures board: name → gate | the team sheet: name → shirt number | the menu: dish name → kitchen station |
| NetworkPolicy | gated community rules: who may drive in | passport control and security zones | the stewards: away fans only enter the away stand | "staff only" doors |
| Ingress / Gateway | the motorway exit signs into the city | the terminal entrance + signs | the stadium gates, routed by ticket type | the maître d' who directs you to a section |

---

## 1. Linux networking you need on the nodes 🟡 MEDIUM

You'll `ssh` to nodes in the exam. These are the commands to read a node's network:
```bash
ip a                          # interfaces + IPs (eth0 = node IP, cali*/veth* = pod ends, tunl0/vxlan = overlay)
ip r                          # routing table ("default via ..." = the gateway)
ip netns                      # network namespaces (each pod has one)
ss -tlnp                      # who listens on which TCP port (exam: "which port does etcd listen on?")
ss -tlnp | grep -E '6443|2379|10250'
cat /proc/sys/net/ipv4/ip_forward              # must be 1 on k8s nodes
sysctl net.bridge.bridge-nf-call-iptables      # must be 1 (needs br_netfilter module)
iptables -t nat -L KUBE-SERVICES | head        # kube-proxy rules (iptables mode)
nslookup / dig, curl, nc -zv host port         # basic connectivity
```

### Ports to know (🔥 the "wrong port" troubleshooting tasks)
| Port | Component |
|---|---|
| 6443 | kube-apiserver |
| 2379 | etcd client (API server → etcd) |
| 2380 | etcd peer (etcd ↔ etcd) |
| 2381 | etcd metrics/health (kubeadm, http, localhost) |
| 10250 | kubelet API |
| 10256 | kube-proxy health |
| 10257 | kube-controller-manager (https) |
| 10259 | kube-scheduler (https) |
| 30000–32767 | NodePort range |
| 53 (UDP+TCP) | CoreDNS (Service `kube-dns` in kube-system) |

---

## 2. The Kubernetes network model and CNI 🟡 MEDIUM (installing a CNI is 🔥 since 2025)

### The 3 rules
1. Every pod gets its **own IP**.
2. Every pod can reach every other pod **directly, without NAT**, on any node.
3. Agents on a node (kubelet) can reach all pods on that node.

Kubernetes **doesn't implement** this. A **CNI plugin** does (Calico, Cilium, Flannel, Weave...).

> [!example]+ Analogies
> - 🛣 **Road builders:** Kubernetes says "every house must have an address and every house must reach every other house". It hires a construction company (CNI) to build the roads. No CNI → houses with no roads → nodes `NotReady` with `network plugin not ready: cni plugin not initialized`, and pods stuck in `ContainerCreating`.
> - 🏢 **Office building:** each pod is an office with its own phone extension. The CNI installs the phone lines between floors (nodes).

### How it's wired
```
kubelet → containerd: "start pod" → containerd creates a network namespace
       → runs the CNI binary from /opt/cni/bin/<plugin>
       → using the config in /etc/cni/net.d/*.conflist   (lowest file name wins)
       → plugin creates a veth pair (one end in the pod, one on the node), assigns an IP from the pod CIDR (IPAM), sets routes
```

```bash
ls /etc/cni/net.d/ ; cat /etc/cni/net.d/*.conflist      # which CNI? (calico, flannel, cilium...)
ls /opt/cni/bin/
k get po -n kube-system -o wide | grep -E 'calico|flannel|cilium|weave'
k get no -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
k -n kube-system get cm kubeadm-config -o yaml | grep -E 'podSubnet|serviceSubnet'
```

### Which CNI supports NetworkPolicy? (🔥 the exam asks you to choose)
| CNI | NetworkPolicy | Notes |
|---|---|---|
| **Calico** | ✅ | most common in exam tasks, install via manifest or Tigera operator |
| **Cilium** | ✅ | eBPF |
| Weave Net | ✅ | old, archived |
| **Flannel** | ❌ | policies are accepted by the API but **do nothing** |

**Exam pattern: "install a CNI that supports NetworkPolicy, pod CIDR X"**:
```bash
# Calico, operator style (the URL/version is given in the task)
k create -f https://raw.githubusercontent.com/projectcalico/calico/vX.Y.Z/manifests/tigera-operator.yaml
curl -O https://raw.githubusercontent.com/projectcalico/calico/vX.Y.Z/manifests/custom-resources.yaml
vim custom-resources.yaml     # spec.calicoNetwork.ipPools[0].cidr: <the cluster's pod CIDR>
k create -f custom-resources.yaml
k get po -n calico-system -w ; k get no      # nodes become Ready
```
Use `k create` for the operator (its CRDs are too big for client-side `apply` annotations).

---

## 3. Services and kube-proxy, the internals 🟡 MEDIUM

> [!example]+ Analogies
> - 📞 **Hotline:** the Service IP is a phone number that no physical phone owns (**virtual IP, you can't ping it**). kube-proxy on every node is the switchboard: "calls to 10.96.12.34:80 → forward to one of these 3 agents".
> - 🍽 **Host at the door:** customers ask for "the restaurant", the host seats them at any free waiter's table.

### kube-proxy modes
| Mode | How | Note |
|---|---|---|
| iptables | NAT rules, random backend | long-time default |
| ipvs | kernel load balancer | deprecated direction, being phased out |
| nftables | nftables rules | newer, GA in recent versions |

```bash
k -n kube-system get ds kube-proxy
k -n kube-system get cm kube-proxy -o yaml | grep -E 'mode|clusterCIDR'
k -n kube-system logs ds/kube-proxy | head     # "Using iptables Proxier" etc.
```

### Where do the CIDRs come from? (🔥 drill 4.5)
| What | Where |
|---|---|
| Service CIDR | `--service-cluster-ip-range` in `/etc/kubernetes/manifests/kube-apiserver.yaml` |
| Pod CIDR (cluster) | `--cluster-cidr` in `kube-controller-manager.yaml`, `kubeadm-config` CM, or the CNI config (Calico IPPool) |
| Pod CIDR (per node) | `k get no -o jsonpath='{.items[*].spec.podCIDR}'` |

### EndpointSlices
The old `Endpoints` API is deprecated (still works, prints a warning). EndpointSlices are the current API:
```bash
k get endpointslices -l kubernetes.io/service-name=web
k describe endpointslice <name>           # addresses, ready conditions, ports
```
Empty endpoints = selector mismatch **or** pods not Ready. That's the #1 Service bug (`break.sh 5`).

### Special Services
- **Headless** (`clusterIP: None`): DNS returns the **pod IPs** instead of one VIP. For StatefulSets: `db-0.db.ns.svc.cluster.local`.
- **ExternalName**: DNS CNAME to an outside name, no proxying.
- **Service without selector**: you write the EndpointSlice yourself (point to an external DB IP).
- `sessionAffinity: ClientIP` = the same client keeps hitting the same pod (🍽 your usual waiter).
- `externalTrafficPolicy: Local` = NodePort/LB only goes to pods on the node that received the traffic (keeps the client IP).

---

## 4. DNS and CoreDNS 🔥 HIGH

> [!example]+ Analogies
> - 📖 **Phone book:** CoreDNS is the phone book. Every Service gets an entry automatically. Pods look it up instead of memorizing numbers (IPs change; names don't).
> - ✈️ **Departures board:** you look for "Tashkent" (name), the board tells you "Gate 12" (IP).
> - 🏠 **Short names:** inside the same family (namespace) you say "call Mom" (`web`). From another family you need the full name: "Mom of the Abdukhoshimov family" (`web.prod`). The **search list** in `/etc/resolv.conf` is what makes the short name work.

### Record formats
| Object | DNS name |
|---|---|
| Service | `<svc>.<ns>.svc.cluster.local` → ClusterIP |
| Headless Service | `<svc>.<ns>.svc.cluster.local` → all ready pod IPs |
| StatefulSet pod (with headless svc) | `<pod>.<svc>.<ns>.svc.cluster.local` |
| Any pod | `<ip-with-dashes>.<ns>.pod.cluster.local` e.g. `192-168-1-5.default.pod.cluster.local` |
| Named port SRV | `_<port-name>._<proto>.<svc>.<ns>.svc.cluster.local` |

Inside a pod:
```bash
k exec po -- cat /etc/resolv.conf
# nameserver 10.96.0.10                       ← kube-dns Service ClusterIP
# search default.svc.cluster.local svc.cluster.local cluster.local
# options ndots:5                             ← names with <5 dots try the search list first
```
| From a pod in namespace `default` | Works? |
|---|---|
| `web` (svc in default) | ✅ |
| `web` (svc in prod) | ❌ → use `web.prod` |
| `web.prod` | ✅ |
| `web.prod.svc.cluster.local` | ✅ always |

### CoreDNS parts
```bash
k -n kube-system get deploy coredns ; k -n kube-system get svc kube-dns     # the Service is still named kube-dns!
k -n kube-system get cm coredns -o yaml        # the Corefile
k -n kube-system logs -l k8s-app=kube-dns
grep -A2 clusterDNS /var/lib/kubelet/config.yaml   # kubelet tells pods which DNS IP to use
```
```
.:53 {
    errors
    health
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {   ← answers *.cluster.local from the API
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
    }
    forward . /etc/resolv.conf                        ← everything else goes to the node's DNS
    cache 30
    loop
    reload
}
```
Exam-style edits: add `rewrite name ...`, add a stub domain (`example.local:53 { forward . 10.0.0.53 }`), change `forward`. After editing the ConfigMap, the `reload` plugin picks it up, or `k -n kube-system rollout restart deploy coredns`.

### dnsPolicy
| dnsPolicy | Pod uses |
|---|---|
| `ClusterFirst` (default) | CoreDNS |
| `Default` | the **node's** resolv.conf (confusing name!) |
| `ClusterFirstWithHostNet` | CoreDNS, for `hostNetwork: true` pods |
| `None` | only what you put in `dnsConfig` |

### Test DNS (🔥 always with a fresh pod)
```bash
k run dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup web.prod
k run dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup kubernetes.default
```
Use `busybox:1.36` or later 1.x: very old busybox images had a broken `nslookup`.

### DNS troubleshooting order
1. CoreDNS pods Running? (`k -n kube-system get po -l k8s-app=kube-dns`) → if not: image, CrashLoop (often a Corefile typo or `loop` detected).
2. `kube-dns` Service has endpoints?
3. Pod's `/etc/resolv.conf` points to the kube-dns ClusterIP? (kubelet `clusterDNS`)
4. A NetworkPolicy blocks egress to port 53? (very common in NetworkPolicy tasks!)
5. You used the short name across namespaces?

---

## 5. NetworkPolicy 🔥 HIGH

> [!example]+ Analogies
> - 🕺 **Nightclub bouncer with a guest list:** without any policy, the club is open to everyone. As soon as **one** policy selects a pod, that pod gets a bouncer: only people **on the list** get in. Multiple policies = their guest lists are **merged** (OR). There is no "ban list" (no deny rules).
> - 🏟 **Stadium stewards:** "only home fans (podSelector) from our city (namespaceSelector) may enter the home stand, through gate 80 (port)".
> - ✈️ **Airport zones:** egress rules = which gates you may *leave* through. Don't forget the passport office (DNS port 53), or you can't find any gate.

### The rules of the game
1. Pods are **non-isolated** (allow all) until a policy **selects** them.
2. Once selected for Ingress (or Egress), **only what some policy allows** is allowed, in that direction.
3. Policies are **additive** (union). You can't deny with a second policy.
4. Replies to allowed connections are automatically allowed (stateful).
5. It needs a CNI that enforces it (Calico yes, Flannel no).
6. `policyTypes`: if omitted, `Ingress` is always assumed, and `Egress` only if the policy has an `egress:` section.

### Anatomy
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-policy
  namespace: prod                 # policies are namespaced. They select pods in THIS namespace only
spec:
  podSelector:                    # WHICH pods this policy protects. {} = all pods in the namespace
    matchLabels: {role: db}
  policyTypes: [Ingress, Egress]
  ingress:
  - from:                         # list of sources (OR between list items)
    - podSelector: {matchLabels: {role: api}}            # pods in the SAME namespace (prod)
    - namespaceSelector: {matchLabels: {team: ops}}      # ALL pods in namespaces labelled team=ops
    - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: app}}
      podSelector: {matchLabels: {role: api}}            # ← SAME item: api pods IN namespace app (AND)
    - ipBlock:
        cidr: 10.0.0.0/16
        except: [10.0.5.0/24]
    ports:
    - {protocol: TCP, port: 5432}
  egress:
  - to:
    - podSelector: {matchLabels: {role: backup}}
    ports:
    - {protocol: TCP, port: 22}
  - to:                           # allow DNS: without this, egress policies break name lookups
    - namespaceSelector: {}
      podSelector: {matchLabels: {k8s-app: kube-dns}}
    ports:
    - {protocol: UDP, port: 53}
    - {protocol: TCP, port: 53}
```

### 🔥 AND vs OR (the #1 NetworkPolicy question)
```yaml
# OR: two list items ("-" twice) → from api pods in MY ns, OR from ANY pod in ns app
- from:
  - podSelector: {matchLabels: {role: api}}
  - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: app}}

# AND: one list item ("-" once) → only api pods that are IN ns app
- from:
  - podSelector: {matchLabels: {role: api}}
    namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: app}}
```
🎬 OR = "people from Hall 1, or anyone with a VIP ticket". AND = "people from Hall 1 **who also** have a VIP ticket". Count the dashes.

Similarly, `from` and `ports` in the same rule = AND ("from these pods AND on this port").

### Ready-made policies (copy these from memory)
```yaml
# deny all ingress in the namespace
spec: {podSelector: {}, policyTypes: [Ingress]}
# deny all ingress + egress
spec: {podSelector: {}, policyTypes: [Ingress, Egress]}
# allow all ingress (to selected pods)
spec: {podSelector: {}, ingress: [{}], policyTypes: [Ingress]}
# allow all egress
spec: {podSelector: {}, egress: [{}], policyTypes: [Egress]}
```
| You write | Means |
|---|---|
| `ingress:` missing + `policyTypes: [Ingress]` | deny all ingress |
| `ingress: [{}]` | allow all ingress |
| `from: []` or `from` missing in a rule | from anywhere (only ports restrict) |
| `podSelector: {}` in `from` | all pods **in this namespace** |
| `namespaceSelector: {}` in `from` | all pods in **all** namespaces |

Every namespace has the automatic label `kubernetes.io/metadata.name=<name>`. Use it instead of adding your own labels.

### Exam pattern: "choose / write the LEAST permissive policy"
Typically 3 policies are given in files. Read each one and ask: does it allow **exactly** the needed flow (right pods, right namespace, right port), and nothing more? Reject ones with `namespaceSelector: {}` alone, missing ports, or OR where AND was needed. Apply the chosen one, then **test both** the allowed and a not-allowed path:
```bash
k -n prod exec deploy/api -- nc -zv -w2 db 5432          # should work (if nc exists in the image)
k -n prod run t --rm -it --image=busybox:1.36 --restart=Never -- nc -zv -w2 db 5432   # should time out
```

---

## 6. Ingress 🔥 HIGH

> [!example]+ Analogies
> - 🏢 **Office building reception:** one front door (one IP/LoadBalancer). The receptionist reads your visitor slip: "`/billing` → 3rd floor, `/support` → 5th floor" (path rules), "`shop.example.com` → Building B" (host rules).
> - ✈️ **Terminal signs:** one entrance, signs route by destination.
> - An **Ingress object is just the sign**. The **Ingress controller** (nginx, traefik, HAProxy) is the receptionist who reads the signs. **No controller = signs nobody reads** → nothing happens.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  namespace: web
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /     # ingress-nginx only: /pay → / at the backend
spec:
  ingressClassName: nginx            # which controller. Omitted → the default IngressClass (if any)
  tls:
  - hosts: [shop.example.com]
    secretName: shop-tls             # kubernetes.io/tls Secret in the SAME namespace
  rules:
  - host: shop.example.com           # omit host → matches any host
    http:
      paths:
      - path: /pay
        pathType: Prefix             # Prefix: /pay, /pay/, /pay/x  (NOT /payment)
        backend:
          service:
            name: pay-svc            # Service in the SAME namespace as the Ingress
            port: {number: 8080}     # or {name: http}
      - path: /
        pathType: Exact              # Exact: only "/"
        backend: {service: {name: home-svc, port: {number: 80}}}
  defaultBackend:                    # when nothing matches
    service: {name: home-svc, port: {number: 80}}
```

Imperative (fast, and the syntax is in `k create ingress -h`):
```bash
k -n web create ingress shop --class=nginx \
  --rule="shop.example.com/pay*=pay-svc:8080" \
  --rule="shop.example.com/=home-svc:80,tls=shop-tls" $do
# "/pay*" → pathType Prefix ; "/pay" → Exact
k get ingressclass ; k -n web describe ingress shop     # check the backends resolve (no "<error: endpoints not found>")
curl -H "Host: shop.example.com" http://<node-ip>:<ingress-nodeport>/pay
curl --resolve shop.example.com:443:<ip> -k https://shop.example.com/pay
```
> [!warning]
> Traps: wrong `ingressClassName`, Service in another namespace (not allowed), wrong service **port** (it's the Service port, not the targetPort), forgetting `pathType` (required).
Note: the community **ingress-nginx** project announced its retirement (2025–2026), which is one reason the exam now pushes Gateway API. Ingress itself is still a stable API.

---

## 7. Gateway API 🔥 HIGH (new in the curriculum)

> [!example]+ Analogies
> - ✈️ **Airport roles:**
>   - **GatewayClass** = the airport *operator company* ("run by NGINX Inc."). Cluster-scoped, set up once by the infra provider.
>   - **Gateway** = a *terminal* with its entrances (listeners: port 80 HTTP, port 443 HTTPS with a certificate). Owned by the cluster operator.
>   - **HTTPRoute** = the *airline's rules* at that terminal: "passengers for `/v2` → gate B, 80% to the old plane, 20% to the new one". Owned by app teams.
> - ⚽ **Stadium:** GatewayClass = the stadium management company, Gateway = the stadium with its gates, HTTPRoute = the steward instructions per club.
> - 🍽 **Food court:** the mall (GatewayClass) → the food court entrance (Gateway) → signs to each restaurant (HTTPRoutes). Each restaurant puts up its own sign without asking the mall to rebuild the entrance. That's the **role separation** Ingress didn't have.

### Why Gateway API instead of Ingress?
| Ingress | Gateway API |
|---|---|
| one object does everything | split by role (class / gateway / routes) |
| features via vendor annotations (rewrite, weights, headers) | built into the spec: header matching, weights, redirects, rewrites |
| HTTP(S) only | HTTP, gRPC, TLS, TCP/UDP routes |
| no cross-namespace control | `allowedRoutes`, `ReferenceGrant` |

```bash
k get gatewayclass                   # in your lab: "nginx" (after ./cluster/up.sh --gateway)
k api-resources | grep gateway.networking.k8s.io
k explain httproute.spec.rules.matches       # the docs are offline here too
```

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gw
  namespace: web
spec:
  gatewayClassName: nginx
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    hostname: "shop.example.com"     # optional
    allowedRoutes:
      namespaces: {from: Same}       # Same (default) | All | Selector
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "shop.example.com"
    tls:
      mode: Terminate                # TLS ends at the gateway
      certificateRefs:
      - kind: Secret
        name: shop-tls               # kubernetes.io/tls secret (same ns as the Gateway)
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: shop
  namespace: web
spec:
  parentRefs:
  - name: web-gw
    sectionName: https               # attach to ONE listener (optional; omit = all listeners)
  hostnames: ["shop.example.com"]
  rules:
  - matches:
    - path: {type: PathPrefix, value: /pay}      # PathPrefix | Exact | RegularExpression
    backendRefs:
    - {name: pay-svc, port: 8080}
  - matches:
    - headers:
      - {name: x-beta, value: "true"}            # header match
    backendRefs:
    - {name: home-v2, port: 80}
  - matches:
    - path: {type: PathPrefix, value: /}
    backendRefs:                                 # canary: 80/20 split
    - {name: home-v1, port: 80, weight: 80}
    - {name: home-v2, port: 80, weight: 20}
---
# HTTP → HTTPS redirect on the port-80 listener
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: redirect, namespace: web}
spec:
  parentRefs: [{name: web-gw, sectionName: http}]
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect: {scheme: https, statusCode: 301}
```
Other filters: `URLRewrite` (like the nginx rewrite annotation: `urlRewrite: {path: {type: ReplacePrefixMatch, replacePrefixMatch: /}}`), `RequestHeaderModifier`, `RequestMirror`.

### 🔥 Exam pattern: migrate an Ingress to Gateway API
| Ingress field | Gateway API |
|---|---|
| `ingressClassName: nginx` | `Gateway.spec.gatewayClassName: nginx` |
| `tls[].secretName` | Gateway listener `HTTPS` + `tls.certificateRefs` |
| `rules[].host` | `HTTPRoute.spec.hostnames` (and/or listener `hostname`) |
| `paths[].path` + `pathType: Prefix` | `matches[].path: {type: PathPrefix, value: ...}` |
| `pathType: Exact` | `type: Exact` |
| `backend.service.name/port.number` | `backendRefs: [{name, port}]` |
| rewrite-target annotation | `URLRewrite` filter |

Steps: read the Ingress (`k get ing x -o yaml`) → write the Gateway (listeners from `tls` + port 80) → write the HTTPRoute (hostnames, matches, backendRefs) → **check status** → test → delete the Ingress only if asked.
```bash
k -n web get gateway web-gw          # PROGRAMMED=True, an ADDRESS
k -n web describe httproute shop     # Conditions: Accepted=True, ResolvedRefs=True (else: wrong svc name/port, or listener/hostname mismatch)
```
Cross-namespace backends need a `ReferenceGrant` in the backend's namespace (🧊 rarely asked).

---

## 8. Network troubleshooting flow 🔥 HIGH

```
Can't reach the app?
1. Pod Running and Ready?               k get po -o wide
2. App listens on the expected port?    k exec po -- netstat -tlnp  (or ss, or check the image docs / containerPort)
3. Pod IP reachable directly?           k run t --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T2 <podIP>:<port>
4. Service has endpoints?               k get endpointslices -l kubernetes.io/service-name=<svc>
   no → selector vs labels, readiness
5. Service port / targetPort right?     k get svc -o yaml | grep -A5 ports
6. DNS name resolves?                   nslookup <svc>.<ns>
7. NetworkPolicy in the way?            k get netpol -A ; describe the ones selecting the pod
8. NodePort / Ingress / Gateway?        right nodePort, ingressClassName, Host header, route status
9. Node level?                          kube-proxy running? CNI pods running? node Ready?
```

---

## 9. Self-check

1. Can you `ping` a ClusterIP? Why?
2. Pod in ns `a` runs `curl web`; svc `web` is in ns `b`. Fails. Fix?
3. Name of the DNS Service in kube-system? Of the Deployment?
4. Flannel cluster, you create a deny-all NetworkPolicy. Effect?
5. A policy has `podSelector: {}` and `policyTypes: [Egress]` and no egress rules. What can those pods do?
6. One `from` item with both `namespaceSelector` and `podSelector` vs two items. Difference?
7. You added an egress policy and now apps get "bad address" for every name. What did you forget?
8. Ingress created, `curl` gets 404 from nginx for every path. Two likely causes?
9. Which Gateway API object is cluster-scoped and who usually owns it?
10. HTTPRoute shows `ResolvedRefs: False`. Most likely cause?
11. Where do you find the Service CIDR?
12. Nodes `NotReady` right after `kubeadm init`, kubelet log says `cni plugin not initialized`. Fix?

> [!success]- Answers
> 1. No (usually): it's a virtual IP handled by kube-proxy rules for specific ports, not an interface. Test with curl/wget on the port.
> 2. `curl web.b` (or the FQDN `web.b.svc.cluster.local`).
> 3. Service `kube-dns`, Deployment `coredns`.
> 4. Nothing. Flannel doesn't enforce policies.
> 5. No egress at all (including DNS): deny-all egress.
> 6. Same item = AND (those pods in those namespaces). Two items = OR.
> 7. Allow egress to kube-dns on UDP **and** TCP 53.
> 8. Host header doesn't match `host:` (curl without `-H Host:`), or the path/pathType doesn't match. Also: wrong `ingressClassName` → a different/no controller reads it.
> 9. GatewayClass, owned by the infrastructure provider/cluster admin.
> 10. Backend Service name or port wrong (or a cross-namespace backend without ReferenceGrant).
> 11. `--service-cluster-ip-range` in the kube-apiserver manifest (also `kubeadm-config` ConfigMap).
> 12. Install a CNI (e.g. Calico) with the right pod CIDR.

---

## 10. Mini-drills in your kind lab (≈60 min, use `./cluster/up.sh --gateway`)

```bash
# A. Node network reading (5 min): ./cluster/ssh.sh cp → ss -tlnp: find 6443, 2379, 2380, 2381, 10250, 10257, 10259.
#    ls /etc/cni/net.d, ip r (see the routes to other nodes' pod CIDRs).

# B. DNS (10 min): drill 4.2 + read a pod's /etc/resolv.conf. Then break DNS with a deny-all EGRESS policy
#    in a test namespace, see nslookup fail, fix it with the DNS egress rule from §5.

# C. NetworkPolicy AND vs OR (15 min): ns app (pods role=api, role=other), ns np (pod role=db listening on 80, e.g. nginx).
#    Write the AND version: only app/api reaches db. Test from api (works), other (blocked), a pod in np (blocked).
#    Change to the OR version and see what opens up.

# D. Ingress → Gateway migration (20 min): write an Ingress (host shop.local, /pay → pay svc, / → home svc).
#    Then build the equivalent Gateway + HTTPRoute on class nginx. Test via the gateway NodePort:
#    k get svc -A | grep web-gw   (NGF 2.x creates one nginx Service per Gateway, in the Gateway's namespace)
#    docker exec cka-worker curl -s -H 'Host: shop.local' localhost:<nodeport>/pay

# E. Weights (5 min): 80/20 split between two deployments that return different text. curl 20 times, count.

# F. break.sh 5, 6, 7 again (10 min). Each one is a networking problem.
```

---
← [[05-storage]] · [[00 Home|🏠 Home]] · [[07-cluster-maintenance]] →
