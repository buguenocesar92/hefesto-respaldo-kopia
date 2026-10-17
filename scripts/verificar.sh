#!/usr/bin/env bash
# =============================================================================
# verificar.sh - Hefesto Studio, kit de respaldo Kopia
#
# Ejecuta la VERIFICACION REAL de integridad del repositorio y devuelve un
# codigo de salida que se puede usar en un cron o en un monitor.
#
# Codigos de salida:
#   0  OK       - la verificacion paso sin errores
#   1  FALLO    - kopia reporto errores de integridad
#   2  USO      - argumentos incorrectos
#   3  ENTORNO  - falta configuracion, docker o repositorio
#
# -----------------------------------------------------------------------------
# QUE HACE EXACTAMENTE (fuente: https://kopia.io/docs/advanced/consistency/)
# -----------------------------------------------------------------------------
# `kopia snapshot verify` recorre las instantaneas y comprueba que las
# estructuras del indice esten correctas y que cada entrada tenga su blob.
# Eso NO descarga ni descifra los archivos.
#
# Con --verify-files-percent=N, ademas descarga, descifra y descomprime un N%
# aleatorio de los archivos. Eso si detecta bit rot. Con 100 es, en la
# practica, una restauracion de prueba.
#
# Upstream recomienda 100% mensual y al menos 1% diario (que a lo largo del
# ano cubre estadisticamente ~98% de los datos).
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/lib.sh"

titulo "Hefesto Studio - verificacion de integridad Kopia"

PORCENTAJE=""
PARALELISMO=""
MAX_ERRORES=""
ORIGENES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --porcentaje)
      [[ $# -ge 2 ]] || { error "--porcentaje necesita un valor"; exit 2; }
      PORCENTAJE="$2"; shift 2 ;;
    --paralelismo)
      [[ $# -ge 2 ]] || { error "--paralelismo necesita un valor"; exit 2; }
      PARALELISMO="$2"; shift 2 ;;
    --origen)
      [[ $# -ge 2 ]] || { error "--origen necesita un valor"; exit 2; }
      ORIGENES+=("$2"); shift 2 ;;
    -h|--help)
      sed -n '2,26p' "$0"; exit 0 ;;
    *)
      error "Argumento desconocido: $1"; exit 2 ;;
  esac
done

cargar_env "${RAIZ_KIT}/.env"
exigir_var KOPIA_PASSWORD

PORCENTAJE="${PORCENTAJE:-${VERIFICAR_PORCENTAJE:-1}}"
PARALELISMO="${PARALELISMO:-${VERIFICAR_PARALELISMO:-4}}"
# --max-errors=0 es "no parar nunca". Para un servicio-managed tiene mas
# sentido_default seguir y reportar. Por eso el default del .env es 1.
MAX_ERRORES="${MAX_ERRORES:-${VERIFICAR_MAX_ERRORES:-1}}"

# Validar el rango de --verify-files-percent (float entre 0.0 y 100.0,
# segun la ayuda del comando).
if ! awk -v p="${PORCENTAJE}" 'BEGIN{exit !(p>=0 && p<=100)}'; then
  error "--porcentaje debe estar entre 0 y 100 (recibido: ${PORCENTAJE})"
  exit 2
fi

MODO="${MODO:-contenedor}"
[[ "${MODO}" == "contenedor" ]] && comprobar_docker || true

if ! kopia repository status >/dev/null 2>&1; then
  error "No hay repositorio conectado. No puedo verificar nada."
  exit 3
fi

detectar_sha256

# -----------------------------------------------------------------------------
# Ejecutar
# -----------------------------------------------------------------------------
titulo "Ejecutando verificacion"

VERIF=(snapshot verify
  "--verify-files-percent=${PORCENTAJE}"
  "--file-parallelism=${PARALELISMO}"
  "--max-errors=${MAX_ERRORES}")

# Si se pasan origenes concretos, se agregan con --sources (flag
# verificado en cli/command_snapshot_verify.go). Sin esto se verifica TODO el
# repositorio.
if [[ ${#ORIGENES[@]} -gt 0 ]]; then
  for o in "${ORIGENES[@]}"; do
    VERIF+=("--sources=${o}")
  done
  info "Origenes: ${ORIGENES[*]}"
else
  info "Se verifica el repositorio completo (sin --sources)."
fi

info "Porcentaje de archivos descargados y descifrados: ${PORCENTAJE}%"
[[ "${PORCENTAJE}" == "0" || "${PORCENTAJE}" == "0.0" ]] && \
  aviso "Con 0% NO se detectan archivos corruptos: solo se verifica la estructura."
[[ "${PORCENTAJE}" == "100" ]] && \
  aviso "Con 100% se descarga todo el repositorio. Cuesta ancho de banda y tiempo."

mkdir -p "${DIR_TRABAJO}"
REPORTE="${DIR_TRABAJO}/verificacion-$(marca_tiempo).txt"

INICIO="$(marca_tiempo)"
set +e
kopia "${VERIF[@]}" 2>&1 | tee "${REPORTE}"
CODIGO=${PIPESTATUS[0]}
set -e

FIN="$(marca_tiempo)"

# -----------------------------------------------------------------------------
# Informe
# -----------------------------------------------------------------------------
titulo "Resultado"

{
  echo "inicio_utc=${INICIO}"
  echo "fin_utc=${FIN}"
  echo "porcentaje_verificado=${PORCENTAJE}"
  echo "paralelismo=${PARALELISMO}"
  echo "max_errores=${MAX_ERRORES}"
  echo "codigo_salida_kopia=${CODIGO}"
} >> "${REPORTE}"

RESUMEN_SHA="$(sha256_de "${REPORTE}")"
printf '%s  %s\n' "${RESUMEN_SHA}" "$(basename "${REPORTE}")" > "${REPORTE}.sha256"

info "Reporte:      ${REPORTE}"
info "SHA-256:      ${RESUMEN_SHA}"

if [[ ${CODIGO} -eq 0 ]]; then
  ok "VERIFICACION OK. El repositorio es consistente para lo verificado."
  cat <<'FINAL'

Ojo con lo que esto NO prueba:
  - Con porcentaje < 100 no se comprobo cada archivo.
  - Un OK no equivale a una restauracion completa probada.
    Upstream es explicito: "The gold standard for testing the validity of
    backups is to simply restore the snapshot."
  Ver docs/05-RESPALDOS-Y-RESTAURACION.md y scripts/restaurar-desde-cero.md
FINAL
  exit 0
fi

error "VERIFICACION FALLO. kopia devolvio codigo ${CODIGO}."
cat <<'FINAL'

Que hacer ahora:
  1. NO borres ni muevas archivos del repositorio a ciegas.
  2. Revisa el reporte: ${REPORTE}
  3. Consulta la seccion "Repairing Corruption" de upstream:
     https://kopia.io/docs/advanced/consistency/
  4. Si el problema es widespread, evalua restaurar desde una instantanea
     anterior en un repositorio nuevo. Ver scripts/restaurar-desde-cero.md
FINAL
exit 1