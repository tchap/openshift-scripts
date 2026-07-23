# How to Create an AWS Cluster

## Prerequisites

- `oc` CLI
- `podman` and/or `docker`
- `yq`, `jq`
- `GITHUB_USER` env var set to your GitHub username (used by registry token scripts)

### Credentials

The cluster creation flow requires several credentials from different systems. All of these need to be set up before creating your first cluster.

| Credential | Where to get it | What it's used for | Lifetime |
|---|---|---|---|
| **AWS permanent credentials** (access key ID + secret key) | [AWS account setup](https://source.redhat.com/groups/public/openshift/openshift_wiki/openshift_dev_amazon_web_services_aws). Create an IAM access key in the AWS console (IAM > Users > Security credentials > Create access key), then run `aws configure --profile <profile-name>` to save it to `~/.aws/credentials`. | Provisioning and destroying AWS infrastructure (EC2, VPC, Route53, etc.). The installer does not work with temporary SAML/SSO credentials. | Permanent (until rotated) |
| **Red Hat pull secret** | [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret) | Pulling OpenShift container images during cluster installation. Stored in `install-config.yaml` and `openshift-installer-pull-secret.txt`. | Permanent (until revoked) |
| **CI registry OAuth token** | [OAuth token request page](https://oauth-openshift.apps.ci.l2s4.p1.openshiftapps.com/oauth/token/request) | Pulling pre-release images from `registry.ci.openshift.org` — needed by `installerupdate` (via `oc adm release extract`) and embedded in the pull secret for cluster installs from CI builds. | Expires periodically — refresh with `updateciregistrytoken` |


## Shell Aliases

Add these to your `.bashrc`/`.zshrc` (adjust paths as needed):

```bash
alias updateciregistrytoken='"${HOME}/projects/openshift-scripts/auth/update-ci-registry-token.sh"'
alias installerupdate='INSTALLER_DIR="${HOME}/work/clusters/openshift-install" "${HOME}/projects/openshift-scripts/cluster/openshift/update-installer.sh"'
alias createinstallconfig='rm -f "${HOME}/work/conf/ocpcred/install-config.yaml"; "${HOME}/work/clusters/openshift-install/bin/openshift-install" create install-config --dir "${HOME}/work/conf/ocpcred"'
alias createcluster='export KUBECONFIG=${HOME}/work/clusters/cluster0/auth/kubeconfig; cp ${HOME}/work/{conf/ocpcred/install-config.yaml,clusters/cluster0/}; AWS_PROFILE=<your-permanent-credentials-profile> ${HOME}/work/clusters/openshift-install/bin/openshift-install create cluster --dir ${HOME}/work/clusters/cluster0/ --log-level=debug; export KUBEADMIN_PASSWORD="$(cat ${HOME}/work/clusters/cluster0/auth/kubeadmin-password)"; DISABLE_CVO=false ${HOME}/projects/openshift-scripts/cluster/openshift/initialize-cluster.sh username-cluster0'
alias destroycluster='export AWS_PROFILE=<your-permanent-credentials-profile>; ${HOME}/work/clusters/openshift-install/bin/openshift-install destroy cluster --dir ${HOME}/work/clusters/cluster0/ --log-level=debug; unset KUBECONFIG; unset KUBEADMIN_PASSWORD; ${HOME}/projects/openshift-scripts/cluster/openshift/clean-after-deleted-cluster.sh username'
```

## One-Time Setup

1. Set up the credentials listed above and replace `<your-permanent-credentials-profile>` in the aliases with your AWS profile name.

2. Create the workspace directories:

   ```bash
   mkdir -p "$HOME/work/conf/ocpcred"
   mkdir -p "$HOME/work/clusters/openshift-install/bin"
   mkdir -p "$HOME/work/clusters/cluster0/auth"
   ```

3. Use a custom registry auth file to avoid touching your default one:

   ```bash
   export REGISTRY_AUTH_FILE="$HOME/work/conf/ocpcred/auth.json"
   ```

   Add this export to your shell profile so it persists.

4. Get your pull secret from [console.redhat.com](https://console.redhat.com/openshift/install/pull-secret)
   and save it to `$HOME/work/conf/ocpcred/openshift-installer-pull-secret.txt`. This file is used
   by `update-ci-registry-token.sh` to keep the CI registry token up to date. You'll also paste
   this pull secret when `openshift-install create install-config` prompts for it.

## Refresh the CI Registry Token

The CI registry token expires periodically. Run this whenever it does:

```bash
updateciregistrytoken <token>
```

Get the token from the [OAuth token request page](https://oauth-openshift.apps.ci.l2s4.p1.openshiftapps.com/oauth/token/request) — log in with your GitHub account and copy the displayed token.

This updates the pull secret in your install-config and logs you in to `registry.ci.openshift.org`.

This currently somehow may now work. An alternative way is to log into `app.ci` cluster manually and then log in using `podman`.
You will need to do this in case the following `installerupdate` invocation fails:

```bash
$ oc login --server=https://api.ci.l2s4.p1.openshiftapps.com:6443 --web
$ podman login -u=$(oc --context app.ci whoami) -p=$(oc --context app.ci whoami -t) quay-proxy.ci.openshift.org
```

## Create a Cluster

1. Download the latest accepted installer:

   ```bash
   installerupdate
   ```

   This fetches the latest non-rejected CI release and extracts `openshift-install`, `oc`, `kubectl`, and `ccoctl` into `$HOME/work/clusters/openshift-install/`.

2. Generate an install config:

   ```bash
   createinstallconfig
   ```

   The installer will prompt for your platform, region, cluster name, and pull secret.
   After generation, edit `$HOME/work/conf/ocpcred/install-config.yaml` to customize the cluster
   (e.g. instance types, worker/master count, networking) before running `createcluster`.

3. Create the cluster:

   ```bash
   createcluster
   ```

   This copies your install-config, runs the installer (~40 minutes), sets `KUBECONFIG` and `KUBEADMIN_PASSWORD`, then runs `initialize-cluster.sh` which:
   - Creates a `test` project
   - Optionally disables CVO (controlled by `DISABLE_CVO`, defaults to `false`)
     (Can be later achieved by running `oc scale --replicas 0 -n openshift-cluster-version deployments/cluster-version-operator`)
   - Updates your local CA trust store (Arch Linux only)
   - Logs you in to the cluster's image registry

   The script will pause with a prompt before updating certs and logging in to the registry.

## Destroy a Cluster

```bash
destroycluster
```

This tears down the AWS resources, unsets `KUBECONFIG` and `KUBEADMIN_PASSWORD`, and cleans up local state.
