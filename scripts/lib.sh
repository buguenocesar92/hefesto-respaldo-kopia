#!/usr/bin/env bash
# =============================================================================
# lib.sh - funciones compartidas del kit de respaldo Kopia de Hefesto Studio
#
# Uso:  source "$(dirname "$0")/lib.sh"
#
# Este archivo no se ejecuta solo: define funciones y variables comunes.
# Todos los scripts que lo incluyen usan `set -euo pipefail`.
# =============================================================================

# No permitir ejecucion directa: evita que alguien lo corra por error.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "lib.sh no se ejecuta directo. Hacelo: source lib.sh" >&2
  exit 64
fi

set -euo pipefail

# -----------------------------------------------------------------------------
# Rutas
# -----------------------------------------------------------------------------
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_DIR="$(cd "${LIB_DIR}/.." && pwd)"
RAIZ_KIT="${KIT_DIR}"

# Directorio de trabajo del kit: registros y manifiestos.
DIR_TRABAJO="${DIR_TRABAJO:-${RAIZ_KIT}/registros}"
DIR_MANIFIESTOS="${DIR_MANIFIESTOS:-${RAIZ_KIT}/manifiestos}"

# -----------------------------------------------------------------------------
# Presentacion
# -----------------------------------------------------------------------------
# Colores solo si la salida es una terminal de verdad: en un cron o en un log
# redirected, las secuencias de escape ensucian el archivo.
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_OK=$'\033[32m'; C_AVISO=$'\033[33m'
  C_ERR=$'\033[31m'; C_INFO=$'\033[36m'; C_NEGRITA=$'\033[1m'
else
  C_RESET=""; C_OK=""; C_AVISO=""; C_ERR=""; C_INFO=""; C_NEGRITA=""
fi

info()  { printf '%s[INFO]%s %s\n' "${C_INFO}"  "${C_RESET}" "$*"; }
ok()    { printf '%s[ OK ]%s %s\n' "${C_OK}"    "${C_RESET}" "$*"; }
aviso() { printf '%s[AVISO]%s %s\n' "${C_AVISO}" "${C_RESET}" "$*" >&2; }
error() { printf '%s[ERROR]%s %s\n' "${C_ERR}"  "${C_RESET}" "$*" >&2; }

titulo() {
  printf '\n%s%s%s\n' "${C_NEGRITA}" "$*" "${C_RESET}"
}

# Termina con un mensaje. Se usa en vez de `exit 1` pelado para que el log diga
# POR QUE fallo, no solo que fallo.
die() {
  error "$*"
  exit 1
}

# -----------------------------------------------------------------------------
# Entorno
# -----------------------------------------------------------------------------

# Carga el .env sin ejecutar lo que hay adentro como shell.
# `set -a` exporta lo que se lea, y se ignora cualquier linea que no sea
# COMENTARIO=valor. Es deliberado: un .env no es un script.
cargar_env() {
  local archivo="${1:-${RAIZ_KIT}/.env}"
  if [[ ! -f "${archivo}" ]]; then
    die "No existe ${archivo}. Copia .env.example a .env y completa los secretos."
  fi

  local linea clave valor
  while IFS= read -r linea || [[ -n "${linea}" ]]; do
    # Saltar comentarios y lineas vacias.
    [[ "${linea}" =~ ^[[:space:]]*# ]] && continue
    [[ "${linea}" =~ ^[[:space:]]*$ ]] && continue
    [[ "${linea}" != *=* ]] && continue
    clave="${linea%%=*}"
    valor="${linea#*=}"
    # Quitar comillas envolventes si las hay.
    valor="${valor%\"}"; valor="${valor#\"}"
    valor="${valor%\'}"; valor="${valor#\'}"
    export "${clave}=${valor}"
  done < "${archivo}"

  info "Entorno cargado desde ${archivo}"
}

# Falla si falta una variable obligatoria.
exigir_var() {
  local nombre="$1"
  if [[ -z "${!nombre:-}" ]]; then
    die "Falta la variable obligatoria ${nombre}. Revisa .env (ver .env.example)."
  fi
}

# -----------------------------------------------------------------------------
# Sumas de comprobacion SHA-256
# -----------------------------------------------------------------------------
# Linux trae sha256sum; macOS trae shasum. Se detecta el que exista.
detectar_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    SHA256_CMD=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then
    SHA256_CMD=(shasum -a 256)
  else
    die "No encontre sha256sum ni shasum. Instala coreutils (sha256sum)."
  fi
}

# sha256_de <archivo> -> imprime el hash por stdout
sha256_de() {
  local archivo="$1"
  [[ -f "${archivo}" ]] || die "No existe el archivo a resumir: ${archivo}"
  "${SHA256_CMD[@]}" "${archivo}" | awk '{print $1}'
}

# -----------------------------------------------------------------------------
# Como correr kopia
# -----------------------------------------------------------------------------
# Dos modos, para que el mismo script sirva en el servidor de respaldos y en
# una estacion de trabajo:
#
#   MODO=nativo    usa el binario `kopia` del PATH (desarrollo, pruebas)
#   MODO=contenedor (por defecto) usa la imagen oficial, que es la fijada
#                   por digest en compose.yaml
#
# El modo contenedor es el que importa en produccion: garantiza que se usa
# exactamente la version que dice VERSION.md.
MODO="${MODO:-contenedor}"

IMAGE_KOPIA="${IMAGE_KOPIA:-kopia/kopia:0.23.1@sha256:89fd95ee2942880ca00eae964266958a394421ddbdf69bca62e38afc55f5900e}"

# Volumenes compartidos con el servidor.
#
# Estos NOMBRES tienen que coincidir con los que declara compose.yaml bajo
# `volumes: ... name:`. Si se dejaran los nombres logicos (kopia-config),
# Docker Compose les antepondria el prefijo del proyecto y el `docker run` de
# este kit crearia un volumen DISTINTO del que usa el servidor: el script
# crearia un repositorio nuevo y el servidor no lo veria.
#
# A partir del despliegue via Coolify los nombres se parametrizan con
# ${VOLUME_PREFIX:-hefesto} (mismo default que en compose.yaml). Si usas el
# kit con `docker compose` directo, no hace falta tocar nada: el default
# sigue produciendo los mismos volumenes que antes.
VOL_PREFIX="${VOLUME_PREFIX:-hefesto}"
VOL_CONFIG="${VOL_CONFIG:-${VOL_PREFIX}-kopia-config}"
VOL_CACHE="${VOL_CACHE:-${VOL_PREFIX}-kopia-cache}"

# kopia <argumentos...> -> ejecuta kopia en el modo configurado.
# Los argumentos se pasan tal cual, sin reempaquetar.
kopia() {
  if [[ "${MODO}" == "nativo" ]]; then
    command kopia "$@"
  else
    docker run --rm \
      --env KOPIA_PASSWORD \
      -v "${VOL_CONFIG}:/app/config" \
      -v "${VOL_CACHE}:/app/cache" \
      "${IMAGE_KOPIA}" "$@"
  fi
}

# Verifica que este host puede hablar con el demonio de Docker.
comprobar_docker() {
  command -v docker >/dev/null 2>&1 || die "No encontre docker en el PATH."
  docker info >/dev/null 2>&1 || die "Docker responde pero no puedo hablar con el daemon. Revisa permisos (grupo docker) o que el servicio este arriba."
}

comprobar_connected() {
  # `kopia repository status` falla si no hay repositorio conectado.
  if ! kopia repository status >/dev/null 2>&1; then
    die "No hay ningun repositorio conectado en este cliente. Ejecuta primero crear-repositorio.sh (servidor) o kopia repository connect (cliente)."
  fi
}

# -----------------------------------------------------------------------------
# Registro de ejecucion
# -----------------------------------------------------------------------------
# Cada corrida deja un log con fecha y un marcador .completo SOLO al final.
# Si el proceso muere a mitad, queda .en-proceso y no hay .completo: un
# respaldo sin .completo no cuenta como respaldo.
marca_tiempo() { date -u '+%Y%m%dT%H%M%SZ'; }

abrir_registro() {
  local nombre="$1"
  mkdir -p "${DIR_TRABAJO}" "${DIR_MANIFIESTOS}"
  REGISTRO="${DIR_TRABAJO}/${nombre}-$(marca_tiempo).log"
  MARCA_EN_PROCESO="${REGISTRO%.log}.en-proceso"
  MARCA_COMPLETO="${REGISTRO%.log}.completo"
  MANIFIESTO="${DIR_MANIFIESTOS}/${nombre}-$(marca_tiempo).manifiesto.json"
  : > "${REGISTRO}"
  : > "${MARCA_EN_PROCESO}"
  info "Registro: ${REGISTRO}"
}

# Marcar el respaldo como completo. SOLO se llama cuando todo salio bien.
marcar_completo() {
  local resumen_sha="$1"
  printf 'completo=%s\nresumen_sha256=%s\n' "$(marca_tiempo)" "${resumen_sha}" > "${MARCA_COMPLETO}"
  rm -f "${MARCA_EN_PROCESO}"
  ok "Marcado como COMPLETO: ${MARCA_COMPLETO}"
}

# Si el script termina con error, se marca como fallido de forma explicita.
fallar() {
  error "Corrida fallida. Queda ${MARCA_EN_PROCESO:-un registro} y NO hay marca de completo."
  exit 1
}