#!/usr/bin/env bash
# =============================================================================
# 02-respaldo-docker-volume.DEMOSTRACION.sh
#
#  ***  ESTE ARCHIVO ES UNA DEMOSTRACION, NO UNA RECETA DE PRODUCCION.  ***
#
#  Sirve para mostrar el MECANISMO de una copia coherente de un volumen Docker.
#  Antes de usarlo con datos reales, entendé los limites que estan abajo.
# =============================================================================
#
# -----------------------------------------------------------------------------
# EL PROBLEMA REAL
# -----------------------------------------------------------------------------
# Kopia respalda ARCHIVOS. Si una base de datos o una aplicacion esta
# ESCRIBIENDO mientras Kopia lee el volumen, el snapshot queda internamente
# consistente (el indice de Kopia siempre esta bien) pero el CONTENIDO puede
# estar a medias: un archivo truncado, un registro escrito a la mitad.
#
# Eso no lo arregla Kopia. Lo arregla detener al escritor.
#
# -----------------------------------------------------------------------------
# LO QUE NO DEBES HACER
# -----------------------------------------------------------------------------
#   * No respolders el volumen crudo de una base de datos en produccion.
#     Postgres, MySQL, Mongo y similares tienen su propia herramienta de
#     volcado (pg_dump, mysqldump, mongodump) que garantiza consistencia.
#     Respaldá EL VOLCADO, no el volumen.
#
#   * No assumes que parar el contenedor es una pausa inocua. La aplicacion
#     puede necesitar mas tiempo para cerrar archivos, o puede quedar en un
#     estado que no le guste al reinicio.
#
#   * Este script NO incluye logica de reintento, de verificacion ni de
#     alerta. Para produccion, operacionalizalo.
#
# -----------------------------------------------------------------------------
# USO
# -----------------------------------------------------------------------------
#   NOMBRE_VOLUMEN=datos_app CONTENEDOR=app_datos \
#     ./02-respaldo-docker-volume.DEMOSTRACION.sh
#
# -----------------------------------------------------------------------------
# REQUISITOS
# -----------------------------------------------------------------------------
#   * El servidor de respaldos debe estar en el mismo host Docker que el
#     volumen, o tener el volumen montado por NFS.
#   * Si el servidor de respaldos esta en otro host, no vas a tener /var/lib/
#     docker/volumes. Este ejemplo solo sirve para host unico.
# =============================================================================

set -euo pipefail

# --- Marcado como demostracion cada vez que corre -------------------------
echo "ATENCION: esto es una DEMOSTRACION, no un procedimiento de produccion." >&2

# -----------------------------------------------------------------------------
# Configuracion
# -----------------------------------------------------------------------------
NOMBRE_VOLUMEN="${NOMBRE_VOLUMEN:?define NOMBRE_VOLUMEN}"
CONTENEDOR="${CONTENEDOR:?define CONTENEDOR}"

RAIZ_KIT="$(cd "$(dirname "$0")/.." && pwd)"

RUTA_VOLUMEN="/var/lib/docker/volumes/${NOMBRE_VOLUMEN}/_data"

# -----------------------------------------------------------------------------
# 1. Comprobaciones previas
# -----------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Este ejemplo necesita root para leer los volumenes de Docker." >&2
  exit 1
fi

if [[ ! -d "${RUTA_VOLUMEN}" ]]; then
  echo "No existe ${RUTA_VOLUMEN}." >&2
  echo "Verifica el nombre con: docker volume ls" >&2
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -qx "${CONTENEDOR}"; then
  echo "El contenedor '${CONTENEDOR}' no esta corriendo." >&2
  echo "Si esta detenido, no hace falta pausarlo: respaldalo directo." >&2
  CONTENEDOR=""
fi

# -----------------------------------------------------------------------------
# 2. El respaldo
# -----------------------------------------------------------------------------
# El pausado y el reanudado NO se hacen aca: se le pasan a respaldar.sh, que
# los ejecuta con una trampa (trap) para que los escritores SIEMPRE vuelvan a
# levantarse, incluso si el respaldo falla a mitad de camino.
#
# Si el contenedor ya estaba detenido, no hay nada que pausar: se respalda
# directo, que es justamente el caso fácil.
ARG_PAUSA=()
ARG_REANUDAR=()

if [[ -n "${CONTENEDOR}" ]]; then
  echo "El respaldo va a detener ${CONTENEDOR} mientras toma la instantanea."
  ARG_PAUSA=(--pausar "docker stop ${CONTENEDOR}")
  ARG_REANUDAR=(--reanudar "docker start ${CONTENEDOR}")
else
  echo "El contenedor esta detenido. No hace falta pausar nada."
fi

"${RAIZ_KIT}/scripts/respaldar.sh" \
  --fuente "${RUTA_VOLUMEN}" \
  --etiqueta "docker-${NOMBRE_VOLUMEN}" \
  "${ARG_PAUSA[@]}" \
  "${ARG_REANUDAR[@]}"

# -----------------------------------------------------------------------------
# 3. Verificacion
# -----------------------------------------------------------------------------
# respaldar.sh deja un manifiesto y un SHA-256, pero eso solo prueba que el
# manifiesto no cambio. Para probar que los DATOS son recuperables hay que
# verificar de verdad. Es el punto que separa a un respaldo de una hypothesis.
#
# Comenta esta linea en un servidor de desarrollo para probarla.
# "${RAIZ_KIT}/scripts/verificar.sh" --porcentaje 1

cat <<'FINAL'

Demo terminada.

Recuerda:
  - esto_respaldado_puede_estar_inconsistente si la app seguia escribiendo.
  - un respaldo recien hecho es una HIPOTESIS: corre verificar.sh.
  - para una base de datos, respalda el VOLCADO, no el volumen.
FINAL