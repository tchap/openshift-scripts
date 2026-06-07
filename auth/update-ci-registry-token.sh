#!/bin/env bash

set -e

API_TOKEN="${1}"

if [[ -z "${API_TOKEN}" ]]; then
    xdg-open "https://oauth-openshift.apps.ci.l2s4.p1.openshiftapps.com/oauth/token/request"
    echo "API token is required!" >&2
    exit 1
fi

GITHUB_USER="${GITHUB_USER:-}"

if [[ -z "${GITHUB_USER}" ]]; then
  echo "GITHUB_USER env var is required" >&2
  exit 1
fi

REGISTRY_URL="${REGISTRY_URL:-registry.ci.openshift.org}"
AUTH_INFO="${GITHUB_USER}:${API_TOKEN}"
AUTH_INFO_BASE64="$(echo -n "${AUTH_INFO}" | base64 -w 0)"

INSTALL_CONFIG="${INSTALL_CONFIG:-"${HOME}/work/conf/ocpcred/install-config.yaml"}"
PULL_SECRET="${PULL_SECRET:-"${HOME}/work/conf/ocpcred/openshift-installer-pull-secret.txt"}"

podman login "${REGISTRY_URL}" -u "${GITHUB_USER}" -p "${API_TOKEN}"

if type docker &> /dev/null; then
  docker login "${REGISTRY_URL}" -u "${GITHUB_USER}" -p "${API_TOKEN}"
fi

if [[ -f "${INSTALL_CONFIG}" ]]; then
  cp "${INSTALL_CONFIG}" "${INSTALL_CONFIG}~"

  CURRENT_PS="$(yq -r '.pullSecret' "${INSTALL_CONFIG}")"
  UPDATED_PS="$(echo "${CURRENT_PS}" | jq -c --arg auth "${AUTH_INFO_BASE64}" \
    '.auths["registry.ci.openshift.org"] = {"auth": $auth}')"

  grep -v '^pullSecret:' "${INSTALL_CONFIG}" > "${INSTALL_CONFIG}.tmp"
  echo "pullSecret: '${UPDATED_PS}'" >> "${INSTALL_CONFIG}.tmp"
  mv "${INSTALL_CONFIG}.tmp" "${INSTALL_CONFIG}"

  echo "updated install config"
fi

if [[ -f "${PULL_SECRET}" ]]; then
  cp "${PULL_SECRET}" "${PULL_SECRET}~"

  UPDATED_PS="$(jq -c --arg auth "${AUTH_INFO_BASE64}" \
    '.auths["registry.ci.openshift.org"] = {"auth": $auth}' "${PULL_SECRET}")"

  echo "${UPDATED_PS}" > "${PULL_SECRET}"

  echo "updated pull secret"
fi
