# Infra recipes. Run `just` to list them.
#
# Unlock Bitwarden once per shell before anything that needs secrets:
#   export BW_SESSION="$(bw unlock --raw)"

set shell := ["bash", "-euo", "pipefail", "-c"]
set dotenv-load := true

# OpenTofu state lives outside the repo. Back this folder up.
state_dir := env_var_or_default("INFRA_STATE_DIR", env_var("HOME") + "/.infra-state")
secrets   := justfile_directory() + "/scripts/with-secrets.sh"

default:
    @just --list

# Install the client tooling in WSL
setup:
    ./scripts/setup-wsl.sh

# Format OpenTofu code
fmt:
    tofu fmt -recursive tofu/

# Check OpenTofu and Ansible without touching any infrastructure
validate:
    for d in tofu/bootstrap tofu/prod; do \
        [ -f "$d/versions.tf" ] || continue; \
        export TF_DATA_DIR="$PWD/$d/.terraform-validate"; \
        tofu -chdir="$d" init -backend=false -input=false > /dev/null; \
        tofu -chdir="$d" validate; \
    done
    cd ansible && for p in site.yml bootstrap.yml; do ansible-playbook "$p" --syntax-check; done

# Initialise an OpenTofu layer (bootstrap or prod)
init layer="bootstrap":
    mkdir -p "{{state_dir}}" && chmod 700 "{{state_dir}}"
    {{secrets}} tofu -chdir=tofu/{{layer}} init -input=false -backend-config="path={{state_dir}}/{{layer}}.tfstate"

# Show what OpenTofu would change
plan layer="bootstrap": (init layer)
    {{secrets}} tofu -chdir=tofu/{{layer}} plan -input=false -out=plan.tfplan

# Apply the saved plan
apply layer="bootstrap":
    {{secrets}} tofu -chdir=tofu/{{layer}} apply -input=false plan.tfplan

# Show what Ansible would change
check playbook="site.yml":
    cd ansible && {{secrets}} ansible-playbook {{playbook}} --check --diff

# Run Ansible for real
converge playbook="site.yml":
    cd ansible && {{secrets}} ansible-playbook {{playbook}}

# Forget SSH host keys so freshly rebuilt machines are accepted
forget-hosts:
    rm -f ~/.ssh/infra_known_hosts

# Rebuild the bootstrap layer (more steps are added as they are written)
rebuild: forget-hosts
    just plan bootstrap
    @read -r -p "Apply the bootstrap plan? [y/N] " a && [ "$a" = "y" ]
    just apply bootstrap
    just converge bootstrap.yml

# Pin the Ubuntu cloud image release, for example: just set-image 20260918
set-image release:
    ./scripts/set-image.sh {{release}}

# Initialise OpenBao once and store the recovery keys in Bitwarden
openbao-init:
    {{secrets}} ./scripts/openbao-init.sh

# Set up policies, AppRoles and an admin user, then revoke the root token
openbao-configure:
    {{secrets}} ./scripts/openbao-configure.sh
