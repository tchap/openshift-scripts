#!/bin/env bash

set -e

INSTALLER_DIR="${INSTALLER_DIR:-}"
CHANNEL=${1:-5.0.0-0.ci}
DOWNGRADE="${DOWNGRADE:-0}"
RELEASE_CONTROLLER="https://amd64.ocp.releases.ci.openshift.org"

function mvsafe() {
  if [[ -e "${1}" ]]; then
    mv "${1}" "${2}"
  fi
}

if [[ -z "${INSTALLER_DIR}" ]]; then
  echo "INSTALLER_DIR env var is required" >&2
  exit 1
fi

RELEASE_JSON="$(curl -s "${RELEASE_CONTROLLER}/api/v1/releasestream/${CHANNEL}/latest?rel=${DOWNGRADE}")"
RELEASE="$(echo "${RELEASE_JSON}" | jq -r '.name')"
PULL_SPEC="$(echo "${RELEASE_JSON}" | jq -r '.pullSpec')"

if [[ -z "${RELEASE}" ]] || [[ "${RELEASE}" == "null" ]]; then
  echo "no accepted release found for channel ${CHANNEL}" >&2
  exit 1
fi

pushd "${INSTALLER_DIR}"
  if [[ -f ./bin/openshift-install ]] && [[ $(./bin/openshift-install version) =~ ${RELEASE} ]]; then
    echo "installer is already at latest version ${RELEASE}"
    exit 0
  fi


  mkdir -p ./bin
  echo "downloading ${RELEASE} release..."

  set -e
  oc adm release extract --tools "${PULL_SPEC}"
  set +e

  mvsafe ./bin/openshift-install openshift-install.bak
  tar -xzf "openshift-install-linux-${RELEASE}.tar.gz"
  rm  "openshift-install-linux-${RELEASE}.tar.gz"
  mv ./openshift-install ./bin/openshift-install

  mvsafe ./oc ./oc.bak
  mvsafe ./kubectl ./kubectl.bak
  tar -xzf "openshift-client-linux-${RELEASE}.tar.gz"
  rm "openshift-client-linux-${RELEASE}.tar.gz"

  mvsafe ./ccoctl ./ccoctl.bak
  tar -xzf "ccoctl-linux-${RELEASE}.tar.gz"
  rm "ccoctl-linux-${RELEASE}.tar.gz"
popd
