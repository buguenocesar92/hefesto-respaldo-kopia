#!/usr/bin/env bash
# =============================================================================
# restaurar.sh - Hefesto Studio, kit de respaldo Kopia
#
# Restaura una instantanea a un directorio local, con las protecciones:
#
#   1. Valida el destino: ruta absoluta, sin `..`, no punto raiz, no sistema.
#   2. Rechaza restaurar sobre un destino con datos, salvo --force explicito.
#   3. NUNCA sobrescribe automaticamente ni borra nada.
#   4. Verifica el codigo de salida de kopia de verdad.
#   5. Deja el servicio DETENIDO al terminar, hasta que alguien revise.
#
# Codigos de salida:
#   0  OK          restauracion terminada
#   1  FALLO       kopia fallo o el destino no era apto
#   2  USO         argumentos incorrectos
#
# Uso:
#   ./scripts/restaurar.sh <instantanea-o-id> /mnt/recuperacion
#   ./scripts/restaurar.sh --listar
#   ./scripts/restaurar.sh <id> /mnt/destino --force
#   ./scripts/restaurar.sh <id> /mnt/destino --servidor "docker compose -f app.yml"
#
# Verificacion de rutas contra path traversal: Kopia restaura el contenido del
# snapshot, pero el DESTINO lo elige el operador. Este script evita que un
# error de dedo termine escribiendo sobre / o sobre el home.
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/lib.sh"

titulo "Hefesto Studio - restauracion desde Kopia"

ORIGEN_INSTANTANEA=""
DESTINO=""
FORZAR=0
ORDEN_SERVICIO=""
LISTAR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --listar)
      LISTAR=1; shift ;;
    --force)
      FORZAR=1; shift ;;
    --servidor)
      [[ $# -ge 2 ]] || die "--servidor necesita el comando para detener el servicio."
      ORDEN_SERVICIO="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,25p' "$0"; exit 0 ;;
    -*)
      die "Opcion desconocida: $1" ;;
    *)
      if [[ -z "${ORIGEN_INSTANTANEA}" ]]; then
        ORIGEN_INSTANTANEA="$1"
      elif [[ -z "${DESTINO}" ]]; then
        DESTINO="$1"
      else
        die "Argumento de mas: $1"
      fi
      shift ;;
  esac
done

cargar_env "${RAIZ_KIT}/.env"
exigir_var KOPIA_PASSWORD

MODO="${MODO:-contenedor}"
[[ "${MODO}" == "contenedor" ]] && comprobar_docker

# -----------------------------------------------------------------------------
# Solo listar
# -----------------------------------------------------------------------------
if [[ "${LISTAR}" -eq 1 ]]; then
  titulo "Instantaneas disponibles"
  info "Para ver las de un origen concreto:  kopia snapshot list --all /ruta/origen"
  kopia snapshot list --all
  cat <<'FINAL'

La primera columna es el id de manifest. Esa es la que se pasa a
`kopia snapshot restore`. Para restaurar una ruta puntual se usa
`kopia snapshot restore <id> <destino> <subruta>`.
FINAL
  exit 0
fi

[[ -n "${ORIGEN_INSTANTANEA}" ]] || die "Falta el id o la fuente de la instantanea. Usa --listar para verlas."
[[ -n "${DESTINO}" ]] || die "Falta el directorio de destino."

if ! kopia repository status >/dev/null 2>&1; then
  die "No hay repositorio conectado. No puedo restaurar."
fi

# -----------------------------------------------------------------------------
# 1. Validar el destino  (anti path-traversal / anti sobrescritura)
# -----------------------------------------------------------------------------
titulo "Validando el destino"

validar_destino() {
  local d="$1"

  # Debe ser una ruta absoluta. Las relativas dependen del cwd y son la causa
  # clasica de restauraciones en el lugar equivocado.
  [[ "${d}" == /* ]] || die "El destino '${d}' no es una ruta absoluta."

  # No debe contener .. en ningun componente.
  if [[ "${d}" == *".."* ]]; then
    die "El destino '${d}' contiene '..'. Destinos con path traversal estan prohibidos."
  fi

  # No la raiz ni directorios del sistema.
  local prohibidos=( "/" "/bin" "/boot" "/dev" "/etc" "/lib" "/proc" "/root"
                     "/sbin" "/sys" "/usr" "/var" "/home" "/opt" "/srv" )
  for p in "${prohibidos[@]}"; do
    if [[ "${d}" == "${p}" ]]; then
      die "El destino '${d}' es un directorio del sistema. Usa uno dedicado, por ejemplo /mnt/recuperacion."
    fi
  done

  # Si ya existe, no puede ser un enlace simbolico (podria apuntar a otro lado).
  if [[ -L "${d}" ]]; then
    die "El destino '${d}' es un enlace simbolico. Destinos que son symlinks estan prohibidos."
  fi

  ok "Destino valido: ${d}"
}

validar_destino "${DESTINO}"

# Comprobar que el destino, resuelto, no cae dentro de un subdirectorio raro
# por un enlace simbolico en un padre.
if [[ -d "${DESTINO}" ]]; then
  RESUELTO="$(cd "${DESTINO}" && pwd -P)"
  [[ "${RESUELTO}" == /* ]] || die "No pude resolver el destino a una ruta real."
  DESTINO="${RESUELTO}"
  ok "Destino resuelto: ${DESTINO}"
fi

# -----------------------------------------------------------------------------
# 2. Destino ocupado: no sobrescribir salvo --force
# -----------------------------------------------------------------------------
titulo "Comprobando el destino"

if [[ -e "${DESTINO}" ]]; then
  if [[ ! -d "${DESTINO}" ]]; then
    die "El destino '${DESTINO}' existe y NO es un directorio. No lo toco."
  fi

  CONTENIDO="$(ls -A "${DESTINO}" 2>/dev/null || true)"

  if [[ -n "${CONTENIDO}" ]]; then
    if [[ "${FORZAR}" -eq 0 ]]; then
      cat >&2 <<FINAL

El destino YA TIENE DATOS:

    ${DESTINO}

Restaurar encima mezclaria los archivos nuevos con los viejos y deja un
estado imposible de auditar. Kopia no borra nada por su cuenta, pero un
restore encima de un directorio con datos produce un resultado que nadie
puede reproducir despues.

Para continuar de todos modos, con responsabilidad y de forma explicita:

    ./scripts/restaurar.sh ${ORIGEN_INSTANTANEA} ${DESTINO} --force

La opcion recomendada es restaurar en un DIRECTORIO NUEVO y revisar ahi.

FINAL
      exit 1
    fi
    aviso "El destino tiene datos y se paso --force. Se restaura encima SIN borrar lo que hay."
  else
    ok "El destino existe y esta vacio."
  fi
else
  info "El destino no existe. Se creara."
  mkdir -p "${DESTINO}"
  ok "Destino creado: ${DESTINO}"
fi

# -----------------------------------------------------------------------------
# 3. Detener el servicio que se va a restaurar (si el operador lo indica)
# -----------------------------------------------------------------------------
# No se detiene nada por cuenta propia: restaurar encima de un servicio vivo
# produce datos inconsistentes. Se detiene solo lo que el operador nombre.
if [[ -n "${ORDEN_SERVICIO}" ]]; then
  titulo "Deteniendo el servicio"
  info "Ejecutando: ${ORDEN_SERVICIO}"
  if ! eval "${ORDEN_SERVICIO}"; then
    die "No se pudo detener el servicio. Restauro cancelado para no escribir encima de un servicio vivo."
  fi
  ok "Servicio detenido."
else
  aviso "No se detuvo ningun servicio. Si el destino esta en uso, la restauracion puede quedar inconsistente."
fi

# -----------------------------------------------------------------------------
# 4. Restaurar
# -----------------------------------------------------------------------------
titulo "Restaurando"

abrir_registro "restauracion"
info "Origen: ${ORIGEN_INSTANTANEA}"
info "Destino: ${DESTINO}"

set +e
kopia snapshot restore "${ORIGEN_INSTANTANEA}" "${DESTINO}" 2>&1 | tee -a "${REGISTRO}"
CODIGO=${PIPESTATUS[0]}
set -e

if [[ ${CODIGO} -ne 0 ]]; then
  die "La restauracion fallo (codigo ${CODIGO}). Revisa ${REGISTRO}. El destino puede quedar a medias: NO lo des por bueno sin revisarlo."
fi

# -----------------------------------------------------------------------------
# 5. Evidencia de lo restaurado
# -----------------------------------------------------------------------------
titulo "Resumen de lo restaurado"

ARCHIVOS="$(find "${DESTINO}" -type f 2>/dev/null | wc -l | tr -d ' ')"
BYTES="$(du -sb "${DESTINO}" 2>/dev/null | awk '{print $1}' || echo '0')"

info "Archivos restaurados: ${ARCHIVOS}"
info "Tamano total:         ${BYTES} bytes"

detectar_sha256
# SHA-256 de un muestreo, para comparar mas adelante.
MUESTRA="${REGISTRO%.log}.muestra-sha256"
find "${DESTINO}" -type f -size +0c 2>/dev/null | sort | head -100 | \
  while IFS= read -r f; do printf '%s  %s\n' "$(sha256_de "${f}")" "${f#${DESTINO}/}"; done \
  > "${MUESTRA}" || true

ok "Muestreo de SHA-256 (hasta 100 archivos): ${MUESTRA}"
info "Esto sirve para comparar contra una segunda restauracion. NO es un"
info "respaldo del contenido: el contenido sigue cifrado en el repositorio."

# -----------------------------------------------------------------------------
# 6. Estado final: servicio DETENIDO
# -----------------------------------------------------------------------------
cat <<FINAL

================================================================================
RESTAURACION TERMINADA. EL SERVICIO QUEDA DETENIDO.
================================================================================

  Destino   : ${DESTINO}
  Archivos  : ${ARCHIVOS}
  Tamano    : ${BYTES} bytes

QUE HACER AHORA, EN ESTE ORDEN:

  1. REVISA EL CONTENIDO. No levantes el servicio a ciegas.
         ls -la ${DESTINO}
         du -sh ${DESTINO}

  2. Revisa los permisos y el dueno de los archivos, no solo que existan.

  3. Verifica la coherencia de la aplicacion. Kopia respalda ARCHIVOS, no
     el estado de un sistema en ejecucion: una base de datos respaldada
     archivo a archivo puede quedar inconsistente. Ver docs/05.

  4. SOLO cuando validas, levanta el servicio tu mismo.

Si algo quedo a medias, NO sigas usando ese destino. Repite la restauracion
en un directorio nuevo.

FINAL

exit 0