#!/usr/bin/env bash
# Create the "cka" practice cluster.
#   ./cluster/up.sh                 -> Kubernetes v1.37.0 (exam version)
#   K8S=v1.36.4 ./cluster/up.sh     -> older version
#   ./cluster/up.sh --gateway       -> also install Gateway API + NGINX Gateway Fabric
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

K8S="${K8S:-v1.37.0}"
CALICO=v3.33.0
METRICS=v0.9.1
NGF=2.8.0

if kind get clusters 2>/dev/null | grep -qx cka; then
  echo "Cluster 'cka' already exists. ./cluster/down.sh to recreate."; exit 0
fi

kind create cluster --config kind-cka.yaml --image "kindest/node:${K8S}"
kubectl config use-context kind-cka

echo ">> Calico ${CALICO}"
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO}/manifests/calico.yaml"

echo ">> metrics-server ${METRICS} (needed for 'kubectl top' and HPA)"
kubectl apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS}/components.yaml"
# kind kubelets use self-signed certs
kubectl -n kube-system patch deploy metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

echo ">> Waiting for nodes to be Ready"
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Exam control-plane nodes have etcdctl; kind nodes don't, so copy ours in.
for b in etcdctl etcdutl; do
  command -v "$b" >/dev/null && docker cp "$(command -v "$b")" "cka-control-plane:/usr/local/bin/$b"
done

if [[ "${1:-}" == "--gateway" ]]; then
  echo ">> Gateway API CRDs + NGINX Gateway Fabric ${NGF}"
  kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v${NGF}" | kubectl apply -f -
  helm upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric --version "${NGF}" \
    -n nginx-gateway --create-namespace \
    --set nginx.service.type=NodePort \
    --wait
fi

kubectl get nodes -o wide
echo
echo "Ready. Default StorageClass 'standard' (local-path) is pre-installed by kind."
echo "Get a shell on a node like the exam's 'ssh node01':  docker exec -it cka-worker bash"
