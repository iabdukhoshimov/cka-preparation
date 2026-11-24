# CKA practice shell. Everything here you can (and should) type yourself in the
# first 60 seconds of the exam. The exam terminal already has `k` + completion.

command -v kubectl >/dev/null || return 0

alias k=kubectl
source <(kubectl completion bash)
complete -o default -F __start_kubectl k

# Practice with these EXACT variables so muscle memory carries into the exam:
export do="--dry-run=client -o yaml"   # k run web --image=nginx $do > pod.yaml
export now="--force --grace-period 0"  # k delete pod web $now

# Switch namespace quickly (exam questions often say "in namespace X")
kn() { kubectl config set-context --current --namespace="$1"; }

# Explain a field path fast: kx pod.spec.containers.securityContext
kx() { kubectl explain "$@" --recursive | less; }

export KUBE_EDITOR=vim
export EDITOR=vim
