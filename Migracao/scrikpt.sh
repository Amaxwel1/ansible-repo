#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"

: "${SRC_API:?Defina SRC_API}"
: "${DST_API:?Defina DST_API}"
: "${OCP_USER:?Defina OCP_USER}"
: "${OCP_PASSWORD:?Defina OCP_PASSWORD}"

TEST_IMAGE="${TEST_IMAGE:-registry.access.redhat.com/ubi9/ubi-minimal:latest}"
BAD_IMAGE="${BAD_IMAGE:-quay.invalid/nao-existe:latest}"
WORKDIR="${WORKDIR:-/tmp/lab_migracao_apps_api}"
SRC_KUBECONFIG="${WORKDIR}/src.kubeconfig"
DST_KUBECONFIG="${WORKDIR}/dst.kubeconfig"

NS_BIL="ag-bkg-teste-ansible-bil-1"
NS_DIL="ag-bkg-teste-ansible-dil-1"
NS_DDS_1="ag-bkg-teste-ansible-valemobi-dds-1"
NS_DDS_2="ag-bkg-teste-ansible-valemobi-2"
NS_PM="ag-bkg-teste-ansible-valemobi-1"
NS_SINV_1="ag-bkg-teste-ansible-sinv-1"
NS_SINV_2="ag-bkg-teste-ansible-sinv-2"

ALL_NAMESPACES=(
  "$NS_BIL"
  "$NS_DIL"
  "$NS_DDS_1"
  "$NS_DDS_2"
  "$NS_PM"
  "$NS_SINV_1"
  "$NS_SINV_2"
)

mkdir -p "$WORKDIR"

login_clusters() {
  echo "[INFO] Login cluster origem"
  oc login "$SRC_API" -u "$OCP_USER" -p "$OCP_PASSWORD" \
    --insecure-skip-tls-verify=true \
    --kubeconfig="$SRC_KUBECONFIG" >/dev/null

  echo "[INFO] Login cluster destino"
  oc login "$DST_API" -u "$OCP_USER" -p "$OCP_PASSWORD" \
    --insecure-skip-tls-verify=true \
    --kubeconfig="$DST_KUBECONFIG" >/dev/null
}

oc_src() {
  oc --kubeconfig="$SRC_KUBECONFIG" "$@"
}

oc_dst() {
  oc --kubeconfig="$DST_KUBECONFIG" "$@"
}

ensure_ns() {
  local kube="$1"
  local ns="$2"

  if ! oc --kubeconfig="$kube" get ns "$ns" >/dev/null 2>&1; then
    oc --kubeconfig="$kube" new-project "$ns" >/dev/null
  fi
}

apply_dc() {
  local kube="$1"
  local ns="$2"
  local dc_name="$3"
  local replicas="$4"
  local image="$5"
  local mode="$6"

  local readiness_block=""
  if [ "$mode" = "ready-timeout" ]; then
    readiness_block='
          readinessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - exit 1
            initialDelaySeconds: 3
            periodSeconds: 5
            failureThreshold: 1000'
  fi

  oc --kubeconfig="$kube" -n "$ns" apply -f - <<EOF
apiVersion: apps.openshift.io/v1
kind: DeploymentConfig
metadata:
  name: ${dc_name}
  labels:
    app: ${dc_name}
    lab: migracao-apps
spec:
  replicas: ${replicas}
  revisionHistoryLimit: 2
  selector:
    app: ${dc_name}
  strategy:
    type: Rolling
  template:
    metadata:
      labels:
        app: ${dc_name}
        lab: migracao-apps
    spec:
      terminationGracePeriodSeconds: 5
      containers:
        - name: app
          image: ${image}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              trap : TERM INT
              while true; do
                date
                sleep 30
              done${readiness_block}
  triggers:
    - type: ConfigChange
EOF
}

delete_dc_if_exists() {
  local kube="$1"
  local ns="$2"
  local dc_name="$3"

  oc --kubeconfig="$kube" -n "$ns" delete dc "$dc_name" --ignore-not-found=true >/dev/null 2>&1 || true
}

scale_all_zero() {
  local kube="$1"
  local ns="$2"
  oc --kubeconfig="$kube" -n "$ns" scale dc --all --replicas=0 >/dev/null 2>&1 || true
}

setup_namespaces() {
  for ns in "${ALL_NAMESPACES[@]}"; do
    ensure_ns "$SRC_KUBECONFIG" "$ns"
    ensure_ns "$DST_KUBECONFIG" "$ns"
  done
}

setup_bil() {
  local ns="$NS_BIL"

  apply_dc "$SRC_KUBECONFIG" "$ns" "database-${ns}"    1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$ns" "webserver-${ns}"   1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$ns" "application-${ns}" 1 "$TEST_IMAGE" "ok"

  apply_dc "$DST_KUBECONFIG" "$ns" "database-${ns}"    0 "$TEST_IMAGE" "ok"
  apply_dc "$DST_KUBECONFIG" "$ns" "webserver-${ns}"   0 "$TEST_IMAGE" "ok"
  apply_dc "$DST_KUBECONFIG" "$ns" "application-${ns}" 0 "$TEST_IMAGE" "ok"
}

setup_dil_ready_timeout() {
  local ns="$NS_DIL"

  apply_dc "$SRC_KUBECONFIG" "$ns" "database-${ns}"    1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$ns" "webserver-${ns}"   1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$ns" "application-${ns}" 1 "$TEST_IMAGE" "ok"

  apply_dc "$DST_KUBECONFIG" "$ns" "database-${ns}"    0 "$TEST_IMAGE" "ok"
  apply_dc "$DST_KUBECONFIG" "$ns" "webserver-${ns}"   0 "$TEST_IMAGE" "ok"
  apply_dc "$DST_KUBECONFIG" "$ns" "application-${ns}" 0 "$TEST_IMAGE" "ready-timeout"
}

setup_dds() {
  local ns1="$NS_DDS_1"
  local ns2="$NS_DDS_2"

  # DDS namespace 1
  apply_dc "$SRC_KUBECONFIG" "$ns1" "webserver-${ns1}"   1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$ns1" "application-${ns1}" 1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$ns1" "database-${ns1}"    1 "$TEST_IMAGE" "ok"

  apply_dc "$DST_KUBECONFIG" "$ns1" "webserver-${ns1}"   0 "$TEST_IMAGE" "ok"
  apply_dc "$DST_KUBECONFIG" "$ns1" "application-${ns1}" 0 "$TEST_IMAGE" "ok"
  apply_dc "$DST_KUBECONFIG" "$ns1" "database-${ns1}"    0 "$TEST_IMAGE" "ok"

  # DDS namespace 2
  # webserver começa zerado na origem para testar "Current Pods igual a zero"
  apply_dc "$SRC_KUBECONFIG" "$ns2" "webserver-${ns2}"   0 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$ns2" "application-${ns2}" 1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$ns2" "database-${ns2}"    1 "$TEST_IMAGE" "ok"

  # destino normal
  apply_dc "$DST_KUBECONFIG" "$ns2" "webserver-${ns2}"   0 "$TEST_IMAGE" "ok"
  apply_dc "$DST_KUBECONFIG" "$ns2" "application-${ns2}" 0 "$TEST_IMAGE" "ok"
  apply_dc "$DST_KUBECONFIG" "$ns2" "database-${ns2}"    0 "$TEST_IMAGE" "ok"

  # cenário de timeout de Running no destino
  delete_dc_if_exists "$DST_KUBECONFIG" "$ns2" "application-${ns2}"
  apply_dc "$DST_KUBECONFIG" "$ns2" "application-${ns2}" 0 "$BAD_IMAGE" "ok"

  # cenário de objeto ausente no destino
  delete_dc_if_exists "$DST_KUBECONFIG" "$ns1" "database-${ns1}"
}

setup_paginas_manutencao() {
  local ns="$NS_PM"

  apply_dc "$SRC_KUBECONFIG" "$ns" "application-${ns}" 1 "$TEST_IMAGE" "ok"
  apply_dc "$DST_KUBECONFIG" "$ns" "application-${ns}" 0 "$TEST_IMAGE" "ok"
}

setup_sinv() {
  local ns1="$NS_SINV_1"
  local ns2="$NS_SINV_2"

  apply_dc "$SRC_KUBECONFIG" "$ns1" "application-${ns1}" 1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$ns1" "webserver-${ns1}"   1 "$TEST_IMAGE" "ok"

  apply_dc "$DST_KUBECONFIG" "$ns1" "application-${ns1}" 0 "$TEST_IMAGE" "ok"
  apply_dc "$DST_KUBECONFIG" "$ns1" "webserver-${ns1}"   0 "$TEST_IMAGE" "ok"

  apply_dc "$SRC_KUBECONFIG" "$ns2" "application-${ns2}" 1 "$TEST_IMAGE" "ok"
  apply_dc "$DST_KUBECONFIG" "$ns2" "application-${ns2}" 0 "$TEST_IMAGE" "ok"
}

status_ns() {
  local label="$1"
  local kube="$2"
  local ns="$3"

  echo
  echo "===== ${label} :: ${ns} ====="
  oc --kubeconfig="$kube" -n "$ns" get dc,pods -o wide || true
}

status_all() {
  for ns in "${ALL_NAMESPACES[@]}"; do
    status_ns "ORIGEM" "$SRC_KUBECONFIG" "$ns"
    status_ns "DESTINO" "$DST_KUBECONFIG" "$ns"
  done
}

reset_dest() {
  echo "[INFO] Resetando destino"

  for ns in "${ALL_NAMESPACES[@]}"; do
    scale_all_zero "$DST_KUBECONFIG" "$ns"
  done

  # DIL: volta o timeout de Ready
  delete_dc_if_exists "$DST_KUBECONFIG" "$NS_DIL" "application-${NS_DIL}"
  apply_dc "$DST_KUBECONFIG" "$NS_DIL" "application-${NS_DIL}" 0 "$TEST_IMAGE" "ready-timeout"

  # DDS 2: volta o timeout de Running
  delete_dc_if_exists "$DST_KUBECONFIG" "$NS_DDS_2" "application-${NS_DDS_2}"
  apply_dc "$DST_KUBECONFIG" "$NS_DDS_2" "application-${NS_DDS_2}" 0 "$BAD_IMAGE" "ok"

  # DDS 1: mantém o objeto ausente no destino
  delete_dc_if_exists "$DST_KUBECONFIG" "$NS_DDS_1" "database-${NS_DDS_1}"

  echo "[INFO] Destino resetado"
}

reset_origin() {
  echo "[INFO] Resetando origem"

  # BIL
  apply_dc "$SRC_KUBECONFIG" "$NS_BIL" "database-${NS_BIL}"    1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$NS_BIL" "webserver-${NS_BIL}"   1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$NS_BIL" "application-${NS_BIL}" 1 "$TEST_IMAGE" "ok"

  # DIL
  apply_dc "$SRC_KUBECONFIG" "$NS_DIL" "database-${NS_DIL}"    1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$NS_DIL" "webserver-${NS_DIL}"   1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$NS_DIL" "application-${NS_DIL}" 1 "$TEST_IMAGE" "ok"

  # DDS 1
  apply_dc "$SRC_KUBECONFIG" "$NS_DDS_1" "webserver-${NS_DDS_1}"   1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$NS_DDS_1" "application-${NS_DDS_1}" 1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$NS_DDS_1" "database-${NS_DDS_1}"    1 "$TEST_IMAGE" "ok"

  # DDS 2
  # webserver fica em 0 para manter o cenário Current Pods = 0
  apply_dc "$SRC_KUBECONFIG" "$NS_DDS_2" "webserver-${NS_DDS_2}"   0 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$NS_DDS_2" "application-${NS_DDS_2}" 1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$NS_DDS_2" "database-${NS_DDS_2}"    1 "$TEST_IMAGE" "ok"

  # Pagina de manutenção
  apply_dc "$SRC_KUBECONFIG" "$NS_PM" "application-${NS_PM}" 1 "$TEST_IMAGE" "ok"

  # SINV
  apply_dc "$SRC_KUBECONFIG" "$NS_SINV_1" "application-${NS_SINV_1}" 1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$NS_SINV_1" "webserver-${NS_SINV_1}"   1 "$TEST_IMAGE" "ok"
  apply_dc "$SRC_KUBECONFIG" "$NS_SINV_2" "application-${NS_SINV_2}" 1 "$TEST_IMAGE" "ok"

  echo "[INFO] Origem resetada"
}

reset_all() {
  reset_origin
  reset_dest
}

fix_running_timeout() {
  echo "[INFO] Corrigindo cenário de Running timeout no destino"
  delete_dc_if_exists "$DST_KUBECONFIG" "$NS_DDS_2" "application-${NS_DDS_2}"
  apply_dc "$DST_KUBECONFIG" "$NS_DDS_2" "application-${NS_DDS_2}" 0 "$TEST_IMAGE" "ok"
}

fix_ready_timeout() {
  echo "[INFO] Corrigindo cenário de Ready timeout no destino"
  delete_dc_if_exists "$DST_KUBECONFIG" "$NS_DIL" "application-${NS_DIL}"
  apply_dc "$DST_KUBECONFIG" "$NS_DIL" "application-${NS_DIL}" 0 "$TEST_IMAGE" "ok"
}

destroy_all() {
  echo "[INFO] Removendo namespaces do lab"
  for ns in "${ALL_NAMESPACES[@]}"; do
    oc_src delete project "$ns" --ignore-not-found=true >/dev/null 2>&1 || true
    oc_dst delete project "$ns" --ignore-not-found=true >/dev/null 2>&1 || true
  done
}

setup_all() {
  setup_namespaces
  setup_bil
  setup_dil_ready_timeout
  setup_dds
  setup_paginas_manutencao
  setup_sinv
  echo "[INFO] Lab criado"
  status_all
}

login_clusters

case "$ACTION" in
  setup)
    setup_all
    ;;
  status)
    status_all
    ;;
  reset-dest)
    reset_dest
    status_all
    ;;
  reset-origin)
    reset_origin
    status_all
    ;;
  reset-all)
    reset_all
    status_all
    ;;
  fix-running-timeout)
    fix_running_timeout
    status_all
    ;;
  fix-ready-timeout)
    fix_ready_timeout
    status_all
    ;;
  destroy)
    destroy_all
    ;;
  *)
    echo "Uso:"
    echo "  bash lab_migracao_apps_api.sh setup"
    echo "  bash lab_migracao_apps_api.sh status"
    echo "  bash lab_migracao_apps_api.sh reset-dest"
    echo "  bash lab_migracao_apps_api.sh reset-origin"
    echo "  bash lab_migracao_apps_api.sh reset-all"
    echo "  bash lab_migracao_apps_api.sh fix-running-timeout"
    echo "  bash lab_migracao_apps_api.sh fix-ready-timeout"
    echo "  bash lab_migracao_apps_api.sh destroy"
    exit 1
    ;;
esac