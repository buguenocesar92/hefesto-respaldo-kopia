#!/usr/bin/env bash
# =============================================================================
# crear-repositorio.sh - Hefesto Studio, kit de respaldo Kopia
#
# Crea el repositorio de Kopia sobre el almacenamiento elegido, fija la politica
# de retencion inicial y deja designado al propietario del mantenimiento.
#
# IMPORTANTE: esto se ejecuta UNA SOLA VEZ, antes de levantar el servidor.
# Kopia documenta que hay que crear y configurar el repositorio ANTES de
# arrancar el Repository Server:
#   https://kopia.io/docs/repository-server/#starting-repository-server
#
# Uso:
#   cp .env.example .env    # y completa los secretos
#   ./scripts/crear-repositorio.sh
#
# Escribe el archivo de configuracion en el volumen kopia-config. Despues de
# correr esto, `docker compose up -d` levanta el servidor sobre ese repositorio.
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/lib.sh"

titulo "Hefesto Studio - creacion del repositorio Kopia"

cargar_env "${RAIZ_KIT}/.env"

# -----------------------------------------------------------------------------
# 1. Validacion previa
# -----------------------------------------------------------------------------
exigir_var KOPIA_PASSWORD
exigir_var KOPIA_STORAGE_TYPE

# La clave del repositorio se pasa por KOPIA_PASSWORD. Verificamos que no venga
# con el valor de ejemplo del .env.example: si queda asi, el repositorio queda
# cifrado con una clave publica y el servicio no sirve para nada.
if [[ "${KOPIA_PASSWORD}" == cambia-esto* ]]; then
  die "KOPIA_PASSWORD sigue con el valor de ejemplo. Genera una clave real con openssl rand -base64 48 | tr -d '\n='"
fi

MODO="${MODO:-contenedor}"
if [[ "${MODO}" == "contenedor" ]]; then
  comprobar_docker
fi
detectar_sha256

# -----------------------------------------------------------------------------
# 2. No pisar un repositorio existente
# -----------------------------------------------------------------------------
if kopia repository status >/dev/null 2>&1; then
  aviso "YA existe un repositorio conectado. Este script no pisa nada y sale."
  info "Para ver la politica actual:  kopia policy show --global"
  info "Para cambiar la politica:     kopia policy set --global --keep-daily N"
  exit 0
fi

info "No hay repositorio conectado. Se creara uno nuevo sobre ${KOPIA_STORAGE_TYPE}."

# -----------------------------------------------------------------------------
# 3. Armar el comando de creacion segun el backend
# -----------------------------------------------------------------------------
# Todos los flags de esta seccion estan verificados contra
# https://kopia.io/docs/repositories/ (ver docs/03-VARIABLES-Y-COMO-OBTENERLAS.md)
#
# Identidad del origen: la fijamos con --override-hostname / --override-username
# para que un cambio de hostname del servidor no cree un origen nuevo. Ver
# docs/05-RESPALDOS-Y-RESTAURACION.md, seccion "Identidad del origen".

IDENTIDAD=()
if [[ -n "${KOPIA_IDENTITY_HOST:-}" ]]; then
  IDENTIDAD+=("--override-hostname=${KOPIA_IDENTITY_HOST}")
fi
if [[ -n "${KOPIA_IDENTITY_USER:-}" ]]; then
  IDENTIDAD+=("--override-username=${KOPIA_IDENTITY_USER}")
fi

case "${KOPIA_STORAGE_TYPE}" in
  s3)
    exigir_var KOPIA_S3_BUCKET
    exigir_var KOPIA_S3_ACCESS_KEY
    exigir_var KOPIA_S3_SECRET_ACCESS_KEY
    ARG_CREAR=(repository create s3
      "--bucket=${KOPIA_S3_BUCKET}"
      "--access-key=${KOPIA_S3_ACCESS_KEY}"
      "--secret-access-key=${KOPIA_S3_SECRET_ACCESS_KEY}")
    # Endpoint y region solo para almacenes compatibles con la API S3.
    [[ -n "${KOPIA_S3_ENDPOINT:-}" ]] && ARG_CREAR+=("--endpoint=${KOPIA_S3_ENDPOINT}")
    [[ -n "${KOPIA_S3_REGION:-}"  ]] && ARG_CREAR+=("--region=${KOPIA_S3_REGION}")
    ;;

  azure)
    exigir_var KOPIA_AZURE_CONTAINER
    exigir_var KOPIA_AZURE_STORAGE_ACCOUNT
    ARG_CREAR=(repository create azure
      "--container=${KOPIA_AZURE_CONTAINER}"
      "--storage-account=${KOPIA_AZURE_STORAGE_ACCOUNT}")
    if [[ -n "${KOPIA_AZURE_STORAGE_KEY:-}" ]]; then
      ARG_CREAR+=("--storage-key=${KOPIA_AZURE_STORAGE_KEY}")
    elif [[ -n "${KOPIA_AZURE_SAS_TOKEN:-}" ]]; then
      ARG_CREAR+=("--sas-token=${KOPIA_AZURE_SAS_TOKEN}")
    else
      die "Azure necesita KOPIA_AZURE_STORAGE_KEY o KOPIA_AZURE_SAS_TOKEN."
    fi
    ;;

  b2)
    exigir_var KOPIA_B2_BUCKET
    exigir_var KOPIA_B2_KEY_ID
    exigir_var KOPIA_B2_KEY
    ARG_CREAR=(repository create b2
      "--bucket=${KOPIA_B2_BUCKET}"
      "--key-id=${KOPIA_B2_KEY_ID}"
      "--key=${KOPIA_B2_KEY}")
    aviso "El motor b2 de Kopia NO soporta object lock. Para protegerse del"
    aviso "ransomware con B2 hay que usar el motor s3 con --endpoint. Ver docs/05."
    ;;

  gcs)
    exigir_var KOPIA_GCS_BUCKET
    ARG_CREAR=(repository create gcs "--bucket=${KOPIA_GCS_BUCKET}")
    [[ -n "${KOPIA_GCS_CREDENTIALS_FILE:-}" ]] \
      && ARG_CREAR+=("--credentials-file=${KOPIA_GCS_CREDENTIALS_FILE}")
    ;;

  webdav)
    exigir_var KOPIA_WEBDAV_URL
    exigir_var KOPIA_WEBDAV_USERNAME
    exigir_var KOPIA_WEBDAV_PASSWORD
    ARG_CREAR=(repository create webdav
      "--url=${KOPIA_WEBDAV_URL}"
      "--webdav-username=${KOPIA_WEBDAV_USERNAME}"
      "--webdav-password=${KOPIA_WEBDAV_PASSWORD}")
    ;;

  sftp)
    exigir_var KOPIA_SFTP_PATH
    exigir_var KOPIA_SFTP_HOST
    exigir_var KOPIA_SFTP_USERNAME
    ARG_CREAR=(repository create sftp
      "--path=${KOPIA_SFTP_PATH}"
      "--host=${KOPIA_SFTP_HOST}"
      "--username=${KOPIA_SFTP_USERNAME}")
    if [[ -n "${KOPIA_SFTP_KEYFILE:-}" ]]; then
      ARG_CREAR+=("--keyfile=${KOPIA_SFTP_KEYFILE}")
    else
      exigir_var KOPIA_SFTP_PASSWORD
      ARG_CREAR+=("--sftp-password=${KOPIA_SFTP_PASSWORD}")
    fi
    ;;

  filesystem)
    exigir_var KOPIA_FILESYSTEM_PATH
    ARG_CREAR=(repository create filesystem "--path=${KOPIA_FILESYSTEM_PATH}")
    aviso "ATENCION: un repositorio en filesystem NO protege de la perdida de"
    aviso "este servidor. Sirve para pruebas, no para produccion."
    ;;

  *)
    die "KOPIA_STORAGE_TYPE '${KOPIA_STORAGE_TYPE}' no soportado por este script. Ver https://kopia.io/docs/repositories/ para la lista completa (rclone y gdrive son experimentales en upstream y no se cubren acá)."
    ;;
esac

# -----------------------------------------------------------------------------
# 4. Crear el repositorio
# -----------------------------------------------------------------------------
titulo "Creando el repositorio"
info "Comando: kopia ${ARG_CREAR[*]} ${IDENTIDAD[*]:-}"

# El script NO imprime la clave. Kopia la lee de KOPIA_PASSWORD.
kopia "${ARG_CREAR[@]}" ${IDENTIDAD[@]+"${IDENTIDAD[@]}"}

ok "Repositorio creado."

# -----------------------------------------------------------------------------
# 5. Politica de retencion inicial
# -----------------------------------------------------------------------------
# Kopia tiene la compresion DESACTIVADA por defecto
# (https://kopia.io/docs/faqs/#how-do-i-enable-compression). `zstd` es lo que
# recomienda upstream cuando no sabes que elegir.
titulo "Fijando la politica de retencion global"

POLITICA=(policy set --global
  "--keep-latest=${POLITICA_KEEP_LATEST:-7}"
  "--keep-hourly=${POLITICA_KEEP_HOURLY:-24}"
  "--keep-daily=${POLITICA_KEEP_DAILY:-14}"
  "--keep-weekly=${POLITICA_KEEP_WEEKLY:-8}"
  "--keep-monthly=${POLITICA_KEEP_MONTHLY:-6}"
  "--keep-annual=${POLITICA_KEEP_ANNUAL:-2}")

if [[ -n "${POLITICA_COMPRESSION:-}" && "${POLITICA_COMPRESSION}" != "none" ]]; then
  POLITICA+=("--compression=${POLITICA_COMPRESSION}")
  info "Compresion: ${POLITICA_COMPRESSION}"
else
  info "Compresion: desactivada (por defecto en upstream)"
fi

kopia "${POLITICA[@]}"
ok "Politica global aplicada."

# -----------------------------------------------------------------------------
# 6. Propietario del mantenimiento
# -----------------------------------------------------------------------------
# CRITICO. Upstream: "one repository user@hostname is designated as the
# Maintenance Owner. Other repository users will not attempt to run maintenance
# automatically". Si el propietario queda apagado, NO hay mantenimiento, y la
# deduplicacion deja basura sin purgar: el repositorio crece sin control.
# Fuente: https://kopia.io/docs/advanced/maintenance/
titulo "Designando propietario del mantenimiento"

kopia maintenance set --owner=me
ok "Esta instancia quedo como propietaria del mantenimiento."

if [[ -n "${KOPIA_MAINTENANCE_DIAS:-}" ]]; then
  kopia maintenance set "--full-interval=${KOPIA_MAINTENANCE_DIAS}d"
  info "Mantenimiento completo cada ${KOPIA_MAINTENANCE_DIAS} dias."
fi

# -----------------------------------------------------------------------------
# 7. Comprobacion
# -----------------------------------------------------------------------------
titulo "Comprobacion"

kopia repository status || aviso "repository status devolvio codigo distinto de 0."
kopia maintenance info

# -----------------------------------------------------------------------------
# 8. Resumen para el operador
# -----------------------------------------------------------------------------
titulo "Residuo de la creacion"

# Guardamos un resumen sin secretos, para poder auditar que se creo y cuando.
RESUMEN="${DIR_MANIFIESTOS}/repositorio-$(marca_tiempo).resumen.txt"
mkdir -p "${DIR_MANIFIESTOS}"
{
  echo "creado_en=$(marca_tiempo)"
  echo "storage_type=${KOPIA_STORAGE_TYPE}"
  echo "identidad_host=${KOPIA_IDENTITY_HOST:-<automatico>}"
  echo "identidad_user=${KOPIA_IDENTITY_USER:-<automatico>}"
  echo "keep_latest=${POLITICA_KEEP_LATEST:-7}"
  echo "keep_daily=${POLITICA_KEEP_DAILY:-14}"
  echo "keep_weekly=${POLITICA_KEEP_WEEKLY:-8}"
  echo "keep_monthly=${POLITICA_KEEP_MONTHLY:-6}"
  echo "keep_annual=${POLITICA_KEEP_ANNUAL:-2}"
  echo "compression=${POLITICA_COMPRESSION:-none}"
} > "${RESUMEN}"

info "Resumen de creacion: ${RESUMEN}"

cat <<'FINAL'

Proximos pasos:
  1. Copia la clave del repositorio a un gestor de contrasenas. NO basta con
     que este en este servidor. Si se pierde, los respaldos son inservibles.
  2. Levanta el servidor:      docker compose up -d
  3. Crea los usuarios:        ver docs/04-PRIMERA-CUENTA-Y-USUARIOS.md
  4. Haz el primer respaldo:   ver docs/05-RESPALDOS-Y-RESTAURACION.md
  5. Verifica el repositorio:  ./scripts/verificar.sh

FINAL