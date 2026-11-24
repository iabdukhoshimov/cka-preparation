#!/usr/bin/env bash
# Exam-like "ssh" into a node:  ./cluster/ssh.sh cp | w1 | w2
# Inside you get crictl, kubeadm, kubelet (systemctl/journalctl), /etc/kubernetes, and etcd certs.
case "${1:-cp}" in
  cp) n=cka-control-plane ;;
  w1) n=cka-worker ;;
  w2) n=cka-worker2 ;;
  *)  n="$1" ;;
esac
exec docker exec -it "$n" bash
