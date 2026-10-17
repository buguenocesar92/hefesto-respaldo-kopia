#!/usr/bin/env bash
# =============================================================================
# respaldar.sh - Hefesto Studio, kit de respaldo Kopia
#
# Toma una instantanea (snapshot) de uno o mas origenes y deja registro:
#   - log de la corrida
#   - manifiesto en formato JSON con los datos de la instantanea
#   - SHA-256 del manifiesto
#   - marca `.completo` SOLO si todo salio bien
#
# Si el proceso se muere a mitad, queda `.en-proceso` y NO hay `.completo`.
# Un respaldo sin marca de completo no se considera respaldo.
#
# Uso:
#   ./scripts/respaldar.sh --fuente /srv/datos --etiqueta diario
#   ./scripts/respaldar.sh --fuente /var/lib/postgresql --pausar "docker stop pg" \
#                          --reanudar "docker start pg"
#
# Las rutas tambien pueden venir de RUTAS_RESPALDO en el .env, separadas por
# espacios. Ver .env.example.
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/lib.sh"

titulo "Hefesto Studio - respaldo con Kopia"

# -----------------------------------------------------------------------------
# Argumentos
# -----------------------------------------------------------------------------
FUENTES=()
ETIQUETA="manual"
ORDEN_PAUSA=""
ORDEN_REANUDACAO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fuente)
      [[ $# -ge 2 ]] || die "--fuente necesita un valor."
      FUENTES+=("$2"); shift 2 ;;
    --etiqueta)
      [[ $# -ge 2 ]] || die "--etiqueta necesita un valor."
      ETIQUETA="$2"; shift 2 ;;
    --pausar)
      [[ $# -ge 2 ]] || die "--pausar necesita un comando."
      ORDEN_PAUSA="$2"; shift 2 ;;
    --reanudar)
      [[ $# -ge 2 ]] || die "--reanudar necesita un comando."
      ORDEN_REANUDACAO="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,25p' "$0"; exit 0 ;;
    *)
      die "Argumento desconocido: $1" ;;
  esac
done

# Si no pasaron rutas por linea de comandos, usar las del .env.
cargar_env "${RAIZ_KIT}/.env"
exigir_var KOPIA_PASSWORD

if [[ ${#FUENTES[@]} -eq 0 ]]; then
  # RUTAS_RESPALDO viene separada por espacios en el .env.
  read -r -a FUENTES <<< "${RUTAS_RESPALDO:-}"
fi

if [[ ${#FUENTES[@]} -eq 0 ]]; then
  die "No hay rutas que respaldar. Usa --fuente RUTA o define RUTAS_RESPALDO en el .env."
fi

MODO="${MODO:-contenedor}"
[[ "${MODO}" == "contenedor" ]] && comprobar_docker
detectar_sha256

titulo "Origenes a respaldar"
for f in "${FUENTES[@]}"; do
  # Validacion de ruta: debe ser absoluta y existir. Se evita respaldar por
  # error un path relativo que en realidad apunte a otra cosa.
  [[ "${f}" == /* ]] || die "La ruta '${f}' no es absoluta. Usa una ruta absoluta."
  [[ -e "${f}" ]] || die "La ruta '${f}' no existe en esta maquina."
  ok "${f}"
done

comprobar_connected

# Etiqueta usados en el manifiesto, no en kopia: evita depender de un tag de
# kopia que podria no existir en la version instalada.
NOMBRE_CORRIDA="respaldo-${ETIQUETA}"
abrir_registro "${NOMBRE_CORRIDA}"
INICIO="$(marca_tiempo)"
info "Inicio: ${INICIO}"

# -----------------------------------------------------------------------------
# Copia coherente: detener escritores antes de respaldar
# -----------------------------------------------------------------------------
# Un snapshot de archivos que estan siendo modificados puede quedar
# consistente en el indice pero con archivos a medio escribir. Para eso esta
# --pausar / --reanudar. Ver docs/05-RESPALDOS-Y-RESTAURACION.md seccion
# "Como obtener una copia coherente".
REANUDADO=0

reanudar() {
  if [[ -n "${ORDEN_REANUDACAO}" && "${REANUDADO}" -eq 0 ]]; then
    info "Reanudando escritores: ${ORDEN_REANUDACAO}"
    # Deliberadamente sin `set -e`: si el reanudacion falla igual hay que avisar.
    if eval "${ORDEN_REANUDACAO}"; then
      ok "Escritores reanudados."
    else
      error "FALLO al reanudar los escritores. Revisa el servicio a mano: ${ORDEN_REANUDACAO}"
    fi
    REANUDADO=1
  fi
}

# Si el script muere por cualquier motivo, los escritores quedan reanudados.
trap 'reanudar' EXIT INT TERM

if [[ -n "${ORDEN_PAUSA}" ]]; then
  titulo "Pausando escritores para obtener una copia coherente"
  info "Ejecutando: ${ORDEN_PAUSA}"
  if ! eval "${ORDEN_PAUSA}"; then
    die "No se pudo pausar los escritores: ${ORDEN_PAUSA}"
  fi
  ok "Escritores pausados."
  # Margen para que la aplicacion termine de escribir.
  sleep "${PAUSA_SEGUNDOS:-5}"
fi

# -----------------------------------------------------------------------------
# Instantanea
# -----------------------------------------------------------------------------
titulo "Creando la instantanea"

SALIDA_SNAPSHOT="${DIR_TRABAJO}/.salida-snapshot-$$.txt"
: > "${SALIDA_SNAPSHOT}"
fallos=0

for f in "${FUENTES[@]}"; do
  info "Respaldando ${f} ..."
  if kopia snapshot create "${f}" 2>&1 | tee -a "${SALIDA_SNAPSHOT}"; then
    ok "Instantanea de ${f} creada."
  else
    error "FALLO al respaldar ${f}."
    fallos=$((fallos + 1))
  fi
done

# -----------------------------------------------------------------------------
# Manifiesto
# -----------------------------------------------------------------------------
# Upstream imprime:  uploaded snapshot <manifest-id>
#                      (root <objeto-id>) in 1m42s
# Guardamos ambos identificadores: el primero sirve para restaurar, el segundo
# identifica el contenido.
ID_MANIFIESTO="$(grep -oE 'uploaded snapshot [0-9a-f]{32}' "${SALIDA_SNAPSHOT}" | tail -1 | awk '{print $3}' || true)"
ID_RAIZ="$(grep -oE '\(root k[0-9a-f]+\)' "${SALIDA_SNAPSHOT}" | tail -1 | tr -d '()' | awk '{print $2}' || true)"

titulo "Manifiesto"

# Evidencia cruda: la salida de `snapshot list --json` para esta corrida.
EVIDENCIA="${DIR_MANIFIESTOS}/${NOMBRE_CORRIDA}-$(marca_tiempo).lista-json"
kopia snapshot list --json --all > "${EVIDENCIA}" 2>/dev/null || aviso "No pude capturar el listado JSON (puede ser un repositorio de solo lectura)."

# Escribir el manifiesto. Se hace con cat para no depender de jq.
{
  printf '{\n'
  printf '  "kit": "hefesto-respaldo-kopia",\n'
  printf '  "version_kit": "1.0.0",\n'
  printf '  "corrida": "%s",\n' "${NOMBRE_CORRIDA}"
  printf '  "etiqueta": "%s",\n' "${ETIQUETA}"
  printf '  "inicio_utc": "%s",\n' "${INICIO}"
  printf '  "fin_utc": "%s",\n' "$(marca_tiempo)"
  printf '  "identidad_host": "%s",\n' "${KOPIA_IDENTITY_HOST:-<automatico>}"
  printf '  "identidad_user": "%s",\n' "${KOPIA_IDENTITY_USER:-<automatico>}"
  printf '  "modo_ejecucion": "%s",\n' "${MODO}"
  printf '  "origenes": ['
  sep=""
  for f in "${FUENTES[@]}"; do
    printf '%s\n    "%s"' "${sep}" "${f}"
    sep=","
  done
  printf '\n  ],\n'
  printf '  "instantanea_manifesto_id": "%s",\n' "${ID_MANIFIESTO:-no-reportado}"
  printf '  "instantanea_raiz_id": "%s",\n' "${ID_RAIZ:-no-reportado}"
  printf '  "origenes_con_error": %d,\n' "${fallos}"
  printf '  "estado": "%s"\n' "$([[ ${fallos} -eq 0 ]] && echo "completado" || echo "parcial")"
  printf '}\n'
} > "${MANIFIESTO}"

RESUMEN_SHA="$(sha256_de "${MANIFIESTO}")"
printf '%s  %s\n' "${RESUMEN_SHA}" "$(basename "${MANIFIESTO}")" > "${MANIFIESTO}.sha256"

ok "Manifiesto: ${MANIFIESTO}"
ok "SHA-256:   ${RESUMEN_SHA}"
info "Evidencia: ${EVIDENCIA}"

# -----------------------------------------------------------------------------
# Cierre
# -----------------------------------------------------------------------------
reanudar

if [[ ${fallos} -gt 0 ]]; then
  error "Fallaron ${fallos} origen(es). NO se marca el respaldo como completo."
  exit 1
fi

FIN="$(marca_tiempo)"
{
  echo "---"
  echo "fin_utc=${FIN}"
  echo "duracion_fin=${INICIO} -> ${FIN}"
  echo "manifiesto=${MANIFIESTO}"
  echo "sha256=${RESUMEN_SHA}"
  echo "estado=OK"
} >> "${REGISTRO}"

marcar_completo "${RESUMEN_SHA}"

cat <<FINAL

Respaldo completado.

  Manifiesto : ${MANIFIESTO}
  SHA-256    : ${RESUMEN_SHA}
  Completo   : ${MARCA_COMPLETO}

Un respaldo recien creado todavia es una HIPOTESIS hasta que se verifique.
Corre la verificacion periodica:

    ./scripts/verificar.sh

FINAL