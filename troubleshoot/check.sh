#!/usr/bin/env bash
# Verify your fix:  ./troubleshoot/check.sh <n>
set -uo pipefail

pass() { echo -e "\e[32mPASS\e[0m $*"; exit 0; }
fail() { echo -e "\e[31mFAIL\e[0m $*"; exit 1; }
ready() { [[ "$(kubectl get node "$1" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" == True ]]; }
avail() { kubectl -n "$1" rollout status deploy/"$2" --timeout=60s >/dev/null 2>&1; }

case "${1:-}" in
1)  avail ts1 app && pass "scheduler is back, ts1/app Available" || fail "ts1/app not Available" ;;
2)  ready cka-worker2 || fail "cka-worker2 not Ready"
    [[ "$(docker exec cka-worker2 systemctl is-enabled kubelet)" == enabled ]] \
      && pass "cka-worker2 Ready and kubelet survives reboot" || fail "Ready, but kubelet is not enabled (won't survive reboot)" ;;
3)  ready cka-worker && pass "cka-worker Ready" || fail "cka-worker not Ready" ;;
4)  kubectl get --raw=/readyz >/dev/null 2>&1 && pass "API server healthy" || fail "API server not reachable" ;;
5)  out=$(kubectl -n ts5 run chk-$RANDOM --rm -i --restart=Never --image=busybox -- wget -qO- -T 5 web </dev/null 2>/dev/null)
    grep -q "Welcome to nginx" <<<"$out" && pass "service web serves nginx" || fail "no nginx response via service web" ;;
6)  avail kube-system coredns || fail "coredns not Available"
    out=$(kubectl run chk-$RANDOM --rm -i --restart=Never --image=busybox -- nslookup kubernetes.default.svc.cluster.local </dev/null 2>/dev/null)
    grep -qE "^Address: 10\.96\.0\.1$" <<<"$out" && pass "DNS works" || fail "nslookup kubernetes.default.svc.cluster.local failed" ;;
7)  kubectl -n ts7 get netpol default-deny >/dev/null 2>&1 || fail "you deleted default-deny"
    kubectl -n ts7 exec frontend -- wget -qO- -T 3 backend >/dev/null 2>&1 || fail "frontend can't reach backend"
    kubectl -n ts7 exec other -- wget -qO- -T 3 backend >/dev/null 2>&1 && fail "other CAN reach backend (too open)"
    pass "only frontend reaches backend" ;;
8)  avail ts8 late && pass "controller-manager fixed, ts8/late Available" || fail "ts8/late not Available" ;;
9)  [[ "$(kubectl -n ts9 get pod db -o jsonpath='{.status.phase}')" == Running ]] \
      && pass "ts9/db Running" || fail "ts9/db not Running" ;;
10) avail ts10 api && pass "ts10/api Available" || fail "ts10/api not Available" ;;
*)  echo "usage: $0 <1-10>"; exit 2 ;;
esac
