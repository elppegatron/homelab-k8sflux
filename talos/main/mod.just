set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

set export
export cluster := "main"

[private]
default:
    just -l talos {{ cluster }}

[confirm('Apply Talos config to ' + node + ' [y|N] ?')]
[doc('Apply Talos config to a node')]
apply-node node *args:
    just talos {{ cluster }} render-config "{{ node }}" \
    | talosctl -n "{{ node }}" apply-config -f /dev/stdin {{ args }}

[confirm('Reboot node ' + node + ' [y|N] ?')]
[doc('Reboot a node')]
reboot-node node:
    talosctl -n {{ node }} reboot -m powercycle

[confirm('Upgrade Kubernetes to ' + version + ' [y|N] ?')]
[doc('Upgrade Kubernetes version on the cluster')]
upgrade-k8s version:
    talosctl -n "$(talosctl config info -o yaml | yq -e '.endpoints[0]')" upgrade-k8s --to {{ version }}

[confirm('Upgrade node ' + node + ' [y|N] ?')]
[doc('Upgrade Talos version on a node')]
upgrade-node node *args:
    talosctl -n "{{ node }}" upgrade -i "$(just talos {{ cluster }} machine-image)" -m powercycle --timeout=10m {{ args }}

[doc('Render Talos config for a node')]
[script]
render-config node:
    export CLUSTER="{{ cluster }}"
    export SCHEMATIC="$(just talos {{ cluster }} schematic-id)"
    export CONTROLPLANE="$(just talos {{ cluster }} machine-controller {{ node }})"
    talosctl machineconfig patch <(just template "{{ source_directory() }}/machineconfig.yaml.j2") \
        -p @<(just template "{{ source_directory() }}/nodes/{{ node }}.yaml.j2")

[private]
schematic-id:
    curl -sX POST --data-binary @<(just template "{{ source_directory() }}/schematic.yaml.j2") "https://factory.talos.dev/schematics" \
        | jq -r '.id'

[private]
machine-controller node:
    just template "{{ source_directory() }}/nodes/{{ node }}.yaml.j2" \
        | yq -e 'select(.machine) \
        | (.machine.type == "controlplane") // ""'

[private]
[script]
machine-image:
    export TMPL_ARGS=(
        -D SCHEMATIC="$(just talos {{ cluster }} schematic-id)"
    )
    minijinja-cli "${TMPL_ARGS[@]}" "{{ source_directory() }}/machineconfig.yaml.j2" | yq -e 'select(.machine) | .machine.install.image'



[doc('Download Talos machine image')]
[script]
download-image version="v1.13.5":
    export SCHEMATIC="$(just talos {{ cluster }} schematic-id)"
    curl -fL --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors --progress-bar \
        -o "{{ source_directory() }}/talos-{{ version }}-${SCHEMATIC:0:8}-secureboot.iso" \
        "https://factory.talos.dev/image/${SCHEMATIC}/{{ version }}/metal-amd64-secureboot.iso"
    just log info "Downloaded Talos" version "{{ version }}" schematic "${SCHEMATIC}"