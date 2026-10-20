#!/usr/bin/env bats
# =============================================================================
# tests/coolify-check.bats - pruebas del contrato Coolify sobre composes
#
# Copia scripts/coolify-check.sh al directorio del test (para que KIT_DIR
# apunte al compose que escribimos) y lo corre tal cual. La parte de
# `docker compose config` falla porque no hay daemon en este entorno, pero
# las comprobaciones ESTATICAS del contrato 2 (name: raiz, volumenes con
# name: hardcoded) corren ANTES del render y son las que probamos.
#
# Correr con:  bats tests/
# =============================================================================

setup() {
  BATS_TEST_DIR="$(mktemp -d -t hefesto-coolify.XXXXXXXX)"
  export HOME="${BATS_TEST_DIR}"
  export PATH="/usr/bin:/bin:${PATH}"
}

teardown() {
  rm -rf "${BATS_TEST_DIR}"
}

# Helper: corre coolify-check.sh sobre un compose en el test dir.
correr_sobre() {
  local compose_path="$1"
  local compose_file
  compose_file="$(basename "${compose_path}")"

  # El script calcula KIT_DIR como `dirname(SCRIPT_DIR)`. Lo copiamos a
  # ${BATS_TEST_DIR}/scripts/coolify-check.sh para que KIT_DIR = ${BATS_TEST_DIR}.
  mkdir -p "${BATS_TEST_DIR}/scripts"
  cp "$(dirname "$BATS_TEST_DIRNAME")/scripts/coolify-check.sh" \
     "${BATS_TEST_DIR}/scripts/coolify-check.sh"

  # Stub de `docker` que solo imprime el comando (asi no abortamos
  # el script por falta de daemon: el render falla, pero los chequeos
  # estaticos ya corrieron).
  cat >"${BATS_TEST_DIR}/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker-stub: $*" >&2
exit 1
STUB
  chmod +x "${BATS_TEST_DIR}/docker"
  export PATH="${BATS_TEST_DIR}:${PATH}"

  run bash "${BATS_TEST_DIR}/scripts/coolify-check.sh"
}

@test "coolify-check.sh: detecta 'name:' a nivel raiz aunque este despues de la linea 20" {
  local compose="${BATS_TEST_DIR}/compose.yaml"
  {
    for _ in $(seq 1 25); do printf '# comentario\n'; done
    printf 'name: este-debe-ser-rechazado\n'
    printf 'services:\n  kopia:\n    image: kopia/kopia:stub\n'
  } > "${compose}"

  correr_sobre "${compose}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"tiene 'name:' a nivel raiz"* ]]
}

@test "coolify-check.sh: 'name:' dentro de un volumen con \${VOLUME_PREFIX} NO se confunde con name: raiz" {
  local compose="${BATS_TEST_DIR}/compose.yaml"
  cat >"${compose}" <<'YAML'
services:
  kopia:
    image: kopia/kopia:stub
volumes:
  kopia-config:
    name: ${VOLUME_PREFIX:-hefesto}-kopia-config
YAML

  correr_sobre "${compose}"

  # El error de name raiz NO debe aparecer.
  [[ "$output" != *"tiene 'name:' a nivel raiz"* ]]
}