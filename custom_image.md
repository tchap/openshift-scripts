# Deploying Custom Control Plane Images

This guide covers how to build, push, and deploy a custom operator or operand image
to a test cluster. It uses `cluster-kube-controller-manager-operator` (the operator) and
`kube-controller-manager` (its operand) as examples, but the same approach works for
other control plane operators.

## Prerequisites

- A running cluster with `KUBECONFIG` set (see [aws_cluster.md](aws_cluster.md))
- `podman`, logged in to `quay.io` (`podman login quay.io`)

## Build and Push the Image

Clone the operator repo and make your changes:

```bash
git clone https://github.com/openshift/cluster-kube-controller-manager-operator.git
cd cluster-kube-controller-manager-operator
```

Build the image. Most OpenShift operator repos provide a `make images` target via
[build-machinery-go](https://github.com/openshift/build-machinery-go):

```bash
make images IMAGE_BUILD_BUILDER=podman
```

Alternatively, build directly with podman:

```bash
podman build -t cluster-kube-controller-manager-operator:latest -f Dockerfile.rhel .
```

Tag and push to your Quay repository:

```bash
QUAY_USER="<your quay.io username>"

podman tag cluster-kube-controller-manager-operator:latest \
  "quay.io/${QUAY_USER}/cluster-kube-controller-manager-operator:latest"

podman push "quay.io/${QUAY_USER}/cluster-kube-controller-manager-operator:latest"
```

Make sure the repository is set to **public** on quay.io, or the cluster won't be able to pull it.

## Deploy a Custom Operator Image

CVO manages operator deployments and will revert any changes you make directly. To deploy
a custom image, first mark the operator's Deployment as unmanaged:

```bash
oc patch clusterversion/version --type=merge -p '
  {"spec":{"overrides":[{
    "kind":"Deployment",
    "group":"apps",
    "namespace":"openshift-kube-controller-manager-operator",
    "name":"kube-controller-manager-operator",
    "unmanaged":true
  }]}}'
```

Then replace the image:

```bash
oc set image -n openshift-kube-controller-manager-operator \
  deployment/kube-controller-manager-operator \
  kube-controller-manager-operator=quay.io/${QUAY_USER}/cluster-kube-controller-manager-operator:latest
```

Watch the rollout:

```bash
oc rollout status -n openshift-kube-controller-manager-operator deployment/kube-controller-manager-operator
```

## Deploy a Custom Operand Image

Operands (e.g. `kube-controller-manager`) are not managed by CVO directly — they are managed
by their operator. The operator reads image references from environment variables on its
own Deployment. For KCMO, the relevant env vars are:

| Env var | Controls |
|---|---|
| `IMAGE` | `kube-controller-manager` (hyperkube) |
| `OPERATOR_IMAGE` | The operator itself |
| `CLUSTER_POLICY_CONTROLLER_IMAGE` | Cluster policy controller |

To build a custom hyperkube image, clone `openshift/kubernetes` and build from the
Dockerfile in `openshift-hack/images/hyperkube/`. This image contains `kube-controller-manager`,
`kube-apiserver`, `kube-scheduler`, and `kubelet`:

```bash
git clone https://github.com/openshift/kubernetes.git
cd kubernetes

podman build -t hyperkube:latest -f openshift-hack/images/hyperkube/Dockerfile.rhel .

podman tag hyperkube:latest "quay.io/${QUAY_USER}/hyperkube:latest"
podman push "quay.io/${QUAY_USER}/hyperkube:latest"
```

Since the operator Deployment is already marked unmanaged (from the previous section),
you can patch the env var to point to your custom image:

```bash
oc set env -n openshift-kube-controller-manager-operator \
  deployment/kube-controller-manager-operator \
  IMAGE=quay.io/${QUAY_USER}/hyperkube:latest
```

The operator will detect the change and roll out new `kube-controller-manager` static pods
on each control plane node. Monitor the rollout:

```bash
oc get kubecontrollermanager/cluster -o jsonpath='{.status.nodeStatuses[*].currentRevision}'
```

## Clean Up

Remove the CVO overrides to restore normal management:

```bash
oc patch clusterversion/version --type=merge -p '{"spec":{"overrides":[]}}'
```

CVO will reconcile the operator Deployment back to the payload image, which in turn will
restore the operand images to their defaults.

Note: while overrides are active, the cluster will report as not upgradeable. This is
expected and resolves once overrides are removed.
