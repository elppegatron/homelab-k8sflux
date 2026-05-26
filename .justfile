#!/usr/bin/env -S just --justfile

set shell := ['bash', '-euo', 'pipefail', '-c']

# Talos Recipes
[group: 'Kubernetes']
mod k8s "kubernetes"

# Talos Recipes
[group: 'Talos']
mod talos "talos"

[private]
default:
    just -l

[private]
log lvl msg *args:
    gum log -t rfc3339 -s -l "{{ lvl }}" "{{ msg }}" {{ args }}

[private]
template file *args:
    minijinja-cli "{{ file }}" {{ args }}