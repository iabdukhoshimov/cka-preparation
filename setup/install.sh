#!/usr/bin/env bash
# One-time workstation setup for CKA prep (Arch / Omarchy).
# Run:  bash setup/install.sh      (asks for your sudo password)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PKGS=(
  docker docker-buildx       # container runtime that kind runs on
  kubectl                    # exam uses kubectl 1.37
  kind                       # Kubernetes-in-Docker multi-node clusters
  helm kustomize             # both are in the CKA curriculum now
  etcd                       # provides etcdctl / etcdutl for backup/restore drills
  k9s kubectx stern          # quality-of-life (NOT available in the exam!)
  yq jq vim bash-completion  # exam terminal is vim + bash
)

echo ">> Installing packages: ${PKGS[*]}"
sudo pacman -S --needed --noconfirm "${PKGS[@]}"

echo ">> Enabling Docker and adding $USER to the docker group"
sudo systemctl enable --now docker.service
if ! id -nG "$USER" | grep -qw docker; then
  sudo usermod -aG docker "$USER"
  echo "!! You were added to the 'docker' group. Log out/in (or run: newgrp docker)."
fi

# kind with several nodes needs higher inotify limits, or kube-proxy/kubelet crash-loop.
echo ">> Raising inotify limits for multi-node kind"
sudo tee /etc/sysctl.d/99-kind.conf >/dev/null <<'EOF'
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
EOF
sudo sysctl --system >/dev/null

bash "$REPO/setup/shell.sh"

echo
echo "Done. Next steps:"
echo "  1. newgrp docker   (or log out/in)"
echo "  2. source ~/.bashrc"
echo "  3. ./cluster/up.sh"
