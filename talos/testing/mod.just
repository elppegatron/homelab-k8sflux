set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

set export
export cluster := "testing"

[private]
default:
    just -l talos {{ cluster }}

[confirm('Apply Talos config to ' + node + ' [y|N] ?')]
[doc('Apply Talos config to a node')]
apply-node node *args:
    just talos {{ cluster }} render-config "{{ node }}" \
    | talosctl -n "{{ node }}" apply-config --insecure -f /dev/stdin {{ args }}

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
    #export BW_ITEM_MACHINE_CA="$(bw list items | jq '.[]|select(.name=="talos")')"
    # This is so much dirtier than op :sob:
    export BW_ITEM="$(bw get item d9567a55-859d-4d47-8c14-6db7c24d9f38)"
    export TMPL_ARGS=(
        -D SCHEMATIC="$(just talos {{ cluster }} schematic-id)"
        -D CONTROLPLANE="$(just talos {{ cluster }} machine-controller {{ node }})"
        -D CLUSTER_NAME="$(echo $cluster)"
        -D CLUSTER_ID="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="CLUSTER_ID") | .value')"
        -D CLUSTER_SECRET="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="CLUSTER_SECRET") | .value')"
        -D CLUSTER_TOKEN="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="CLUSTER_TOKEN") | .value')"
        -D MACHINE_CA_CRT="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="MACHINE_CA_CRT") | .value')"
        -D MACHINE_CA_KEY="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="MACHINE_CA_KEY") | .value')"
        -D MACHINE_TOKEN="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="MACHINE_TOKEN") | .value')"
        -D CLUSTER_CA_CRT="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="CLUSTER_CA_CRT") | .value')"
        -D CLUSTER_CA_KEY="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="CLUSTER_CA_KEY") | .value')"
        -D CLUSTER_ETCD_CA_CRT="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="CLUSTER_ETCD_CA_CRT") | .value')"
        -D CLUSTER_ETCD_CA_KEY="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="CLUSTER_ETCD_CA_KEY") | .value')"
        -D CLUSTER_AGGREGATORCA_CRT="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="CLUSTER_AGGREGATORCA_CRT") | .value')"
        -D CLUSTER_AGGREGATORCA_KEY="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="CLUSTER_AGGREGATORCA_KEY") | .value')"
        -D CLUSTER_SERVICEACCOUNT_KEY="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="CLUSTER_SERVICEACCOUNT_KEY") | .value')"
        -D CLUSTER_SECRETBOXENCRYPTIONSECRET="$(echo $BW_ITEM | jq -r '.fields[] | select(.name=="CLUSTER_SECRETBOXENCRYPTIONSECRET") | .value')"
    )
    minijinja-cli "${TMPL_ARGS[@]}" "{{ source_directory() }}/machineconfig.yaml.j2" > .render
    talosctl machineconfig patch <(minijinja-cli "${TMPL_ARGS[@]}" "{{ source_directory() }}/machineconfig.yaml.j2") \
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