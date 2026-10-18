#!/usr/bin/env bash
# =============================================================================
# coolify-check.sh - verifica que los compose files del kit cumplen el contrato
# para desplegar en Coolify (Traefik + Docker Compose build pack).
#
# Chequea los puntos 1 y 2 del contrato del kit con Coolify:
#   1. Nada que salte Traefik ni de poder sobre el host en servicios sin
#      profiles (ports, container_name, privileged, network_mode/pid/ipc host,
#      cap_add, devices, security_opt unconfined, binds fuera del repo o
#      docker.sock).
#   2. Nombres estables sin forzar (sin name: fijo a nivel raiz ni en redes;
#      los volumenes pueden llevar `name:` solo si viene de ${VOLUME_PREFIX}).
#
# Corre `docker compose config` con un .env ficticio (valores no secretos
# tipo `x123...` y `https://ejemplo.invalid` para hosts/URLs) para que el
# render no falle por variables obligatorias sin definir.
#
# Salida: exit 0 si los composes cumplen el contrato, exit 1 en caso contrario.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${KIT_DIR}"

# Colores solo si la salida es una terminal.
if [[ -t 1 ]]; then
  C_OK=$'\033[32m'; C_ERR=$'\033[31m'; C_AVISO=$'\033[33m'; C_RESET=$'\033[0m'
else
  C_OK=""; C_ERR=""; C_AVISO=""; C_RESET=""
fi

ok()    { printf '%s[ OK ]%s %s\n' "${C_OK}"   "${C_RESET}" "$*"; }
aviso() { printf '%s[AVISO]%s %s\n' "${C_AVISO}" "${C_RESET}" "$*" >&2; }
error() { printf '%s[FAIL]%s %s\n' "${C_ERR}"  "${C_RESET}" "$*"; }

# Variables del contrato: defaults por tipo.
# Las variables de URL/host/fingerprint reciben un placeholder valido pero
# inutilizable. El resto recibe `x123...` no secreto.
valor_ficticio() {
  local var="$1"
  case "${var}" in
    KOPIA_TLS_FINGERPRINT)
      printf 'x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef'
      ;;
    KOPIA_TIMEZONE)
      printf 'America/Santiago'
      ;;
    KOPIA_BIND_HOST)
      printf '127.0.0.1'
      ;;
    PUERTO_KOPIA)
      # Necesita un numero de puerto valido para que docker compose config
      # no aborte al renderizar el bloque ports.
      printf '51515'
      ;;
    *)
      # Cualquier otra variable obligatoria recibe un placeholder no secreto.
      printf 'x1234567890abcdef'
      ;;
  esac
}

# Extrae los nombres de variable ${VAR}, ${VAR:-def} y ${VAR:?msg} del compose
# pasado por parametro. Orden unico, estable.
vars_en_compose() {
  local compose="$1"
  grep -oE '\$\{[A-Z_][A-Z0-9_]*(:[?][^}]*|:-[^}]*)?\}' "${compose}" \
    | sed -E 's/^\$\{//; s/[:?-][^}]*\}//; s/\}//' \
    | sort -u
}

# Escribe un .env ficticio al lado y devuelve su ruta en stdout. Combina las
# variables del compose base (si existe) y del compose a verificar, para que
# los overrides reciban todas las variables que necesitan del base.
generar_env_ficticio() {
  local compose="$1"
  local env_archivo
  env_archivo="$(mktemp -t coolify-check.XXXXXXXX.env)"
  {
    if [[ "${compose}" != "compose.yaml" && -f "compose.yaml" ]]; then
      vars_en_compose "compose.yaml"
    fi
    vars_en_compose "${compose}"
  } | sort -u | while IFS= read -r var; do
    [[ -z "${var}" ]] && continue
    printf '%s=%s\n' "${var}" "$(valor_ficticio "${var}")"
  done > "${env_archivo}"
  printf '%s\n' "${env_archivo}"
}

# Comprueba un compose ya renderizado en JSON contra el contrato.
# Imprime "servicio: motivo" por cada incumplimiento y devuelve 1 si hay al
# menos uno.
verificar_contrato() {
  local json="$1" compose="$2"
  local falla=0

  # Listar servicios. Excluir los que estan dentro de un profile.
  local servicios servicio
  servicios="$(printf '%s' "${json}" | jq -r '.services | keys[]')"
  while IFS= read -r servicio; do
    local svc_json
    svc_json="$(printf '%s' "${json}" | jq -c ".services[\"${servicio}\"]")"

    # Saltar servicios en profiles.
    if printf '%s' "${svc_json}" | jq -e 'has("profiles") and (.profiles | type == "array" and length > 0)' >/dev/null; then
      continue
    fi

    # Contrato 1.a: ports.
    if printf '%s' "${svc_json}" | jq -e 'has("ports")' >/dev/null; then
      error "${compose}: servicio '${servicio}': expone 'ports:' al host. Coolify enruta el dominio, no debe haber bind al host"
      falla=1
    fi

    # Contrato 1.b: container_name.
    if printf '%s' "${svc_json}" | jq -e 'has("container_name")' >/dev/null; then
      error "${compose}: servicio '${servicio}': tiene 'container_name'. Coolify asigna el nombre"
      falla=1
    fi

    # Contrato 1.c: privileged.
    if [[ "$(printf '%s' "${svc_json}" | jq -r '.privileged // false')" == "true" ]]; then
      error "${compose}: servicio '${servicio}': tiene 'privileged: true'"
      falla=1
    fi

    # Contrato 1.d: network_mode: host.
    if [[ "$(printf '%s' "${svc_json}" | jq -r '.network_mode // ""')" == "host" ]]; then
      error "${compose}: servicio '${servicio}': usa 'network_mode: host'"
      falla=1
    fi

    # Contrato 1.e: pid/ipc en host.
    local pid_val ipc_val
    pid_val="$(printf '%s' "${svc_json}" | jq -r '.pid // ""')"
    ipc_val="$(printf '%s' "${svc_json}" | jq -r '.ipc // ""')"
    if [[ "${pid_val}" == "host" ]]; then
      error "${compose}: servicio '${servicio}': usa 'pid: host'"
      falla=1
    fi
    if [[ "${ipc_val}" == "host" ]]; then
      error "${compose}: servicio '${servicio}': usa 'ipc: host'"
      falla=1
    fi

    # Contrato 1.f: cap_add / devices.
    if printf '%s' "${svc_json}" | jq -e 'has("cap_add") or has("devices")' >/dev/null; then
      error "${compose}: servicio '${servicio}': define 'cap_add' o 'devices'"
      falla=1
    fi

    # Contrato 1.g: security_opt unconfined.
    local sec_opt
    sec_opt="$(printf '%s' "${svc_json}" | jq -r '.security_opt // [] | .[]')"
    if [[ "${sec_opt}" == *unconfined* ]]; then
      error "${compose}: servicio '${servicio}': usa security_opt 'unconfined'"
      falla=1
    fi

    # Contrato 1.h: bind mounts fuera del repo o a docker.sock. Solo importa
    # los de tipo bind; los volumenes nombrados (type=volume) NO cuentan.
    local mounts
    mounts="$(printf '%s' "${svc_json}" | jq -c '[.volumes // [] | .[] | select(.type == "bind")]')"
    while IFS= read -r mount; do
      [[ -z "${mount}" ]] && continue
      local src
      src="$(printf '%s' "${mount}" | jq -r '.source // ""')"
      if [[ "${src}" == "/var/run/docker.sock" ]]; then
        error "${compose}: servicio '${servicio}': monta docker.sock"
        falla=1
        continue
      fi
      # Los binds deben caer DENTRO del kit. Docker Compose resuelve paths
      # relativos contra project_directory.
      if [[ -n "${src}" && "${src}" != "${KIT_DIR}"/* ]]; then
        error "${compose}: servicio '${servicio}': bind fuera del repo: ${src}"
        falla=1
      fi
    done < <(printf '%s\n' "${mounts}" | jq -c '.[]? // empty')
  done <<<"${servicios}"

  return "${falla}"
}

# --- Proceso principal ------------------------------------------------------
COMPOSES=(compose.yaml compose.tls.yaml)
falla_global=0
env_archivos=()

# Limpiar archivos temporales al salir, sea exito o falla.
trap 'rm -f "${env_archivos[@]:-}"' EXIT

for compose in "${COMPOSES[@]}"; do
  if [[ ! -f "${compose}" ]]; then
    aviso "${compose} no existe, se omite"
    continue
  fi

  printf 'Verificando %s...\n' "${compose}"

  # Contrato 2: comprobaciones estaticas sobre el YAML fuente que el render
  # con interpolacion no preserva (nombre raiz fijo, volumenes con name:
  # hardcoded sin ${VOLUME_PREFIX}).
  # Solo comprobamos el archivo que se esta verificando; en compose.tls.yaml
  # los volumes se redefinen, asi que ese compose los tiene que cumplir tambien.
  if grep -qE '^name:[[:space:]]' "${compose}"; then
    error "${compose}: tiene 'name:' a nivel raiz (Coolify pone el nombre de proyecto)"
    falla_global=1
  fi
  # Volumenes: name: hardcoded sin ${VOLUME_PREFIX}-[...] -> contrato 2 violado.
  # Buscar lineas `name:` dentro de bloques volumes que no usen interpolacion.
  if grep -nE '^[[:space:]]+name:' "${compose}" \
     | grep -vE '^[^:]+:[[:space:]]*name:[[:space:]]*\$\{' >/dev/null; then
    error "${compose}: hay volumenes con 'name:' fijo sin '\${VOLUME_PREFIX}'. Coolify antepone el prefijo del proyecto"
    falla_global=1
  fi

  # Renderizar. Los overrides (compose.tls.yaml) requieren su base; se pasan
  # ambos con -f si el base existe.
  env_archivo="$(generar_env_ficticio "${compose}")"
  env_archivos+=("${env_archivo}")

  flag_compose=(--project-directory "${KIT_DIR}" -f "${compose}")
  if [[ "${compose}" != "compose.yaml" && -f "compose.yaml" ]]; then
    flag_compose=(--project-directory "${KIT_DIR}" -f "compose.yaml" -f "${compose}")
  fi

  if ! json="$(docker compose "${flag_compose[@]}" --env-file "${env_archivo}" config --format json 2>&1)"; then
    error "${compose}: 'docker compose config' fallo"
    printf '%s\n' "${json}"
    falla_global=1
    continue
  fi

  if ! verificar_contrato "${json}" "${compose}"; then
    falla_global=1
  else
    ok "${compose}: cumple el contrato (puntos 1 y 2)"
  fi
done

if [[ "${falla_global}" -ne 0 ]]; then
  error "Uno o mas composes NO cumplen el contrato de Coolify"
  exit 1
fi

ok "Todos los composes cumplen el contrato de Coolify"
