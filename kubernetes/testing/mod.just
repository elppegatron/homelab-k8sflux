set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

set export
export cluster := "testing"
controller := `talosctl config info -o yaml | yq -e '.endpoints[0]'`
nodes := `talosctl config info -o yaml | yq -e '.nodes | join (" ")'`

[private]
default:
    just -l k8s {{ cluster }}

[confirm('Bootstrap cluster? [y|N]')]
[doc('Bootstrap a Talos & Kubernetes cluster end-to-end')]
bootstrap: nodes k8s (kubeconfig "node") base apps kubeconfig

[private]
[script]
nodes:
    just log info "Running stage..." "stage" "$(basename "$0")"
    for n in {{ nodes }}; do
        if ! op=$(just --yes talos {{ cluster }} apply-node "$n" --insecure 2>&1); then
            if [[ "$op" == *"certificate required"* ]]; then
                just log info "Talos already configured, skipping apply of config" "stage" "$(basename "$0")" "node" "$n"
                continue
            fi
            just log fatal "Failed to apply Talos configuration" "stage" "$(basename "$0")" "node" "$n" "output" "$op"
        fi
    done

[private]
[script]
k8s:
    just log info "Running stage..." "stage" "$(basename "$0")"
    until op=$(talosctl -n "{{ controller }}" bootstrap 2>&1 || true) && [[ "$op" == *"AlreadyExists"* ]]; do
        just log info "Kubernetes bootstrap in progress. Retrying in 5 seconds..." "stage" "$(basename "$0")"
        sleep 5
    done

[private]
[script]
kubeconfig lb="cilium":
    just log info "Running stage..." "stage" "$(basename "$0")"
    if ! talosctl kubeconfig --nodes "{{ controller }}" --merge --force --force-context-name {{ cluster }} {{ justfile_dir() }}; then
        just log fatal "Failed to fetch kubeconfig" "stage" "$(basename "$0")"
    fi
    if [[ "{{ lb }}" != "cilium" ]]; then
        if ! kubectl config set-cluster {{ cluster }} --server "https://{{ controller }}:6443"; then
            just log fatal "Failed to set kubectl cluster server address" "stage" "$(basename "$0")"
        fi
    fi

[private]
[script]
base: ready
    just log info "Running stage..." "stage" "$(basename "$0")"
    if ! kustomize build {{ source_directory() }}/bootstrap/kustomize/apps | just template - | kubectl apply --server-side --force-conflicts -f -; then
        just log fatal "Failed to apply base manifests" "stage" "$(basename "$0")" "file" "$f"
    fi
    if ! helmfile -f "{{ source_directory() }}/bootstrap/helmfile/crds.yaml" template -q | yq -e 'select(.kind == "CustomResourceDefinition")' | kubectl apply --server-side --force-conflicts -f -; then
        just log fatal "Failed to apply base crds" "stage" "$(basename "$0")"
    fi

[private]
[script]
apps:
    just log info "Running stage..." "stage" "$(basename "$0")"
    if ! helmfile -f "{{ source_directory() }}/bootstrap/helmfile/apps.yaml" sync --hide-notes; then
        just log fatal "Failed to sync helmfile" "stage" "$(basename "$0")"
    fi

# Wait until nodes register as Ready=False. They only become Ready=True once the CNI is healthy.
[private]
[script]
ready:
    just log info "Running stage..." "stage" "$(basename "$0")"
    if ! kubectl wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then
        until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
            just log info "Nodes not available, waiting for nodes to be available. Retrying in 5 seconds..." "stage" "$(basename "$0")"
            sleep 5
        done
    fi



# Flux Recipes
[group: 'Flux']
[script]
sync-all:
    kubectl get gitrepositories --all-namespaces --no-headers | awk '{print $1, $2}' \
        | xargs --max-procs=4 -l bash -c \
            'kubectl -n $0 annotate gitrepository/$1 reconcile.fluxct.io/requestedAt=$(date +%s) --field-manager=flux-client-side-apply --overwrite'
    kubectl get kustomization --all-namespaces --no-headers | awk '{print $1, $2}' \
        | xargs --max-procs=4 -l bash -c \
            'kubectl -n $0 annotate kustomization/$1 reconcile.fluxcd.io/requestedAt="$(date +%s)" --field-manager=flux-client-side-apply --overwrite'
