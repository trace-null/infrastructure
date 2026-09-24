# infra

OpenTofu and Ansible configuration for my homelab. Contains no secrets.
Real values are supplied at run time from Bitwarden and OpenBao.

## Architecture

Four VMs on Proxmox, provisioned by OpenTofu, configured by Ansible:

| VM                    | Role      | What it does                                    |
|------------------------|-----------|--------------------------------------------------|
| `openbao-1`             | `openbao` | Secrets storage. Everything else reads from here. |
| `gitlab-1`              | `gitlab`  | Source control. Public HTTPS + private SSH (2224), container registry (5050). |
| `gitlab-runner-1`       | `gitlab_runner` | CI runner, docker executor. Stateless, no share. |
| `infrastructure-stack`  | `authentik` | SSO identity provider for GitLab (and future services). |

**Persistence:** VMs are disposable. Each app VM has a ZFS dataset on the
Proxmox host, shared in over virtiofs and mounted at `/mnt/infra`. The
`docker-compose.service` systemd unit for each app `RequiresMountsFor` that
path, so the stack can never start against an empty/wrong disk.

**Secrets flow:**
1. Root credentials (Proxmox API token, OpenTofu state passphrase, OpenBao
   seal key, AppRole IDs) live in Bitwarden, under `infrastructure/*`.
2. `scripts/with-secrets.sh` reads those into a single command's
   environment. Nothing is written to disk.
3. Application secrets (Postgres passwords, OIDC client secrets, deploy
   keys) live in OpenBao under `secret/apps/<name>`, written by hand via
   `bao kv put`.
4. Ansible reads application secrets at converge time via the
   `community.hashi_vault` lookup plugin, authenticating with the
   `ansible` AppRole. Connection details live in
   `ansible/inventory/group_vars/all.yml`, not scattered across roles.

**Compose apps:** `gitlab`, `gitlab_runner` and `authentik` are Docker Compose stacks
and share a `compose_app` Ansible role that handles everything generic:
mounting the share, installing Docker, writing `.env`, installing and
starting the systemd unit. Each app's own role only handles what's
actually specific to it, see below. The share is optional: a stateless
app like the runner leaves `compose_app_share_tag` unset and gets no mount.

**CI runner:** `gitlab-runner-1` is a group runner on the `docker-images`
group, not an instance runner, so only projects in that group can use it.
It runs the docker executor with `privileged = true`, narrowed by
`allowed_privileged_images`/`allowed_privileged_services` so that only
`docker:*-dind` containers actually get privileged. Job containers do not.
Its authentication token (`glrt-...`) lives in OpenBao at
`secret/apps/gitlab-runner` (key `token`), and `config.toml` is rendered
from it on every converge. To replace the runner, create a new one in
GitLab (Admin or group > CI/CD > Runners), `bao kv put` the new token,
converge, then delete the old runner in GitLab.

**Container registry:** served by GitLab on port 5050 of `gitlab-1`, behind
Pangolin at `GITLAB_REGISTRY_HOSTNAME` (from `.env`). Docker clients get
their token from GitLab's internal address, because the public hostname
sits behind Pangolin's auth gate. So only LAN clients can log in.

## Adding a new VM/service

As of the `compose_app` refactor, this is close to the minimum:

**1. OpenTofu** — one new `module` block in `tofu/bootstrap/main.tf`,
copied from an existing one. Only `name`, `vm_id`, `cores`, `memory_mb`,
`disk_gb`, `ip_address`, `tags`, `virtiofs_shares`, and `description`
need to change; everything else comes from `local.vm_defaults` in
`locals.tf`. Add matching `_ip`/`_vm_id` outputs in `outputs.tf`.

**2. Inventory** — one new `_hosts` group and host entry in
`ansible/inventory/hosts.yml`, matching the IP from the Tofu module.

**3. Ansible role** — for a Docker Compose app, the role needs only:
- a settings-present `assert`
- however this app's compose repo gets fetched (public HTTPS clone for
  something open, SSH + deploy key + `known_hosts` trust for something
  private, this genuinely varies per app and stays in the app's own
  role, not the shared one)
- any app-specific secret fetch (`hashi_vault` lookup against its own
  `secret/apps/<name>` path)
- one `include_role: name=compose_app` call, passing `compose_app_name`,
  `compose_app_display_name`, `compose_app_share_tag`,
  `compose_app_share_path`, `compose_app_project_dir`, and
  `compose_app_env` (a dict written straight into `.env`)

**4. `compose_app` handler** — add one line to
`ansible/roles/compose_app/handlers/main.yml`:
`- name: "Apply <app> compose"` running
`systemctl reload-or-restart <app>-compose.service`.
Ansible handlers can't be parameterised by variable in their name, so
this one line per app is the one place shared-role logic still needs a
per-app touch.

**5. Register the app in `bootstrap.yml`** as its own play.

Not a Docker Compose app (like `openbao`, a native binary)?
`compose_app` doesn't apply; write a normal role, `openbao`'s is a
reasonable template for that shape (mount, install, config, systemd,
all explicit).

## Operating

Always run `just` recipes from the repo root, not from inside `ansible/` or `tofu/bootstrap/`, and load `.env` first if calling scripts directly:

    set -a; . ./.env; set +a

Skipping that is the single most common mistake in this repo. Running `with-secrets.sh` without `.env` sourced silently loses `GITLAB_HOSTNAME` etc; running `tofu` without it falls back to a LAN-only Proxmox endpoint and hangs or fails with a DNS timeout instead of an obviously related error.

Common commands:

    just validate                                  # syntax-check everything, no network needed
    just plan bootstrap                             # tofu plan
    just apply bootstrap                            # tofu apply
    just converge bootstrap.yml                     # full ansible run, all hosts
    just converge bootstrap.yml --limit gitlab-1    # one host only

For a check-mode dry run against one host before a real converge:

    cd ansible
    BW_SESSION="$(bw unlock --raw)" ../scripts/with-secrets.sh ansible-playbook bootstrap.yml --check --diff --limit <host>

### Gotchas

- **VM rebuilds change the SSH host key.** Fix: `ssh-keygen -R <ip>`. If another role SSHes into that VM (like `authentik` cloning from `gitlab-1` over 2224), its `known_hosts` entry needs refreshing too. The `authentik` role's host-key-trust task does this automatically via a live `ssh-keyscan` on every run, so it'll show a harmless one-line `changed` diff every time, that's expected, not a bug.

- **`docker` commands on the VMs need `sudo`.** The `ansible` user isn't in the `docker` group.

- **Accessing any VM from outside the LAN needs `pangolin up` running first.** A Pangolin resource toggled off makes everything downstream time out with no obvious cause.

- **Pangolin's own authentication gate must be OFF for any resource that itself handles machine-to-machine OIDC/API traffic** (Authentik's own hostname, for instance). If it's on, backend requests like GitLab's OIDC discovery fetch get intercepted and return a bare `401 text/plain` before reaching the real app, with nothing logged on the receiving service's end. If a service-to-service integration fails with no trace on the receiving side, check this first.

- **A `GITLAB_OMNIBUS_CONFIG` change triggers a full `gitlab-ctl reconfigure`** on next start. Several minutes of `unhealthy` is normal.

- **Vault lookup connection details live in `group_vars/all.yml`** (`vault_addr`, `vault_ca_cert`, `vault_role_id`, `vault_secret_id`), not in per-role defaults or shell env exports. If a new role's `hashi_vault` lookup silently connects to `localhost:8200`, it's using an old pattern, use those four group vars instead.

- **`main` is protected.** All changes go through a PR, no direct pushes.
