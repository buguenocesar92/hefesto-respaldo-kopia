#!/usr/bin/env bats
# =============================================================================
# tests/lib.bats - pruebas unitarias de scripts/lib.sh
#
# Estas pruebas SON RED si la corrección del bug de VOL_PREFIX no esta aplicada:
# el bug congelaba VOL_CONFIG/VOL_CACHE al valor que VOLUME_PREFIX tenia cuando
# lib.sh se sourced, ignorando el valor que `cargar_env` lee del .env despues.
#
# Correr con:  bats tests/
# =============================================================================

setup() {
  # Aislamiento: cada test arranca con un HOME temporal, PATH limpio y un
  # stub de `docker` que solo imprime los argumentos. Asi no dependemos de
  # un daemon real para probar que kopia() arma bien el comando.
  BATS_TEST_DIR="$(mktemp -d -t hefesto-bats.XXXXXXXX)"
  export HOME="${BATS_TEST_DIR}"

  # Stub de docker: en vez de correr, imprime los argumentos uno por linea.
  cat >"${BATS_TEST_DIR}/docker" <<'STUB'
#!/usr/bin/env bash
for a in "$@"; do printf '%s\n' "$a"; done
STUB
  chmod +x "${BATS_TEST_DIR}/docker"
  export PATH="${BATS_TEST_DIR}:${PATH}"

  # .env vacio por defecto para cargar_env (no necesita secretos reales).
  echo "# vacio" > "${BATS_TEST_DIR}/.env"

  # Variables minimas para que cargar_env no aborte y para que kopia()
  # tenga KOPIA_PASSWORD al ejecutar `repository status`.
  export KOPIA_PASSWORD="clave-de-prueba-no-es-secreto"
  export MODO="contenedor"
  export IMAGE_KOPIA="kopia/kopia:stub"

  # Asegurar que NINGUNA variable de prefijo este pre seteada antes de source.
  unset VOLUME_PREFIX VOL_PREFIX VOL_CONFIG VOL_CACHE
}

teardown() {
  rm -rf "${BATS_TEST_DIR}"
}

@test "lib.sh: kopia() usa el VOLUME_PREFIX que cargar_env pone despues del source" {
  # Source primero, con VOLUME_PREFIX sin definir (default "hefesto").
  # shellcheck disable=SC1091
  source "$(dirname "$BATS_TEST_DIRNAME")/scripts/lib.sh"

  # Simular lo que pasa en crear-repositorio.sh / verificar.sh / restaurar.sh:
  # cargar_env se llama DESPUES del source y lee VOLUME_PREFIX del .env.
  VOLUME_PREFIX="cliente1"
  cargar_env "${BATS_TEST_DIR}/.env"

  # Llamar a kopia() debe usar cliente1-kopia-config, no hefesto-kopia-config.
  run kopia repository status

  [ "$status" -eq 0 ]
  [[ "$output" == *"cliente1-kopia-config"* ]]
  [[ "$output" != *"hefesto-kopia-config"* ]]
}

@test "lib.sh: con VOLUME_PREFIX sin definir sigue usando el default hefesto" {
  # shellcheck disable=SC1091
  source "$(dirname "$BATS_TEST_DIRNAME")/scripts/lib.sh"

  cargar_env "${BATS_TEST_DIR}/.env"

  run kopia repository status

  [ "$status" -eq 0 ]
  [[ "$output" == *"hefesto-kopia-config"* ]]
}

@test "lib.sh: VOL_CACHE tambien refleja el VOLUME_PREFIX posterior al source" {
  # shellcheck disable=SC1091
  source "$(dirname "$BATS_TEST_DIRNAME")/scripts/lib.sh"

  VOLUME_PREFIX="otro-cliente"
  cargar_env "${BATS_TEST_DIR}/.env"

  run kopia repository status

  [ "$status" -eq 0 ]
  [[ "$output" == *"otro-cliente-kopia-cache"* ]]
  [[ "$output" != *"hefesto-kopia-cache"* ]]
}