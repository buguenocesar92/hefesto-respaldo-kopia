# 07 — Pruebas de aceptación

> **Estado del kit: `kit preparado`.**
>
> En el entorno donde se construyó este kit **no había Docker, ni un servidor,
> ni un bucket, ni un repositorio**. En consecuencia, **ninguna prueba de
> ejecución de este documento se corrió**. Todo lo que está en la parte de
> arriba es **verificación documental**: se leyó la documentación oficial de
> Kopia y el código fuente del proyecto, y se comprobó que lo que el kit
> afirma coincide con lo que upstream dice.
>
> **No confundas las dos columnas.** La verificación documental es real y útil,
> pero no es una prueba de ejecución.

---

## Parte A — Verificado de verdad (documental)

Cada punto dice **qué se revisó** y **dónde está la fuente**. Esto sí se hizo.

### A.1 Versión e imagen

| # | Verificado | Cómo |
|---|---|---|
| A.1.1 | La última versión estable es **v0.23.1** | `api.github.com/repos/kopia/kopia/releases` → `tag_name: v0.23.1`, `prerelease: False`, `draft: False`, publicada `2026-06-16T01:27:33Z` |
| A.1.2 | El digest del índice multiplataforma es `sha256:89fd95ee...5900e` | API de Docker Hub, tag `0.23.1` |
| A.1.3 | Existen digests por plataforma para amd64, arm64 y arm | Ídem, campo `images[]` |
| A.1.4 | La licencia es **Apache-2.0** | API de GitHub, `license.spdx_id` |
| A.1.5 | v0.23.1 es una corrección de una condición de carrera que puede causar pérdida de datos | Notas de la release v0.23.1 |

### A.2 Comportamiento de la imagen oficial

Leído de `tools/docker/Dockerfile` en el repositorio de Kopia:

| # | Verificado |
|---|---|
| A.2.1 | El `ENTRYPOINT` es `["/bin/kopia"]`. Por eso el `command:` del compose arranca en `server`, no en `kopia server` |
| A.2.2 | `WORKDIR /app` |
| A.2.3 | No hay `USER`: el proceso corre como root. El kit no lo cambia |
| A.2.4 | **No hay `HEALTHCHECK`**. El healthcheck del kit es propio |
| A.2.5 | No hay `EXPOSE` |
| A.2.6 | Variables de entorno de la imagen: `KOPIA_CONFIG_PATH=/app/config/repository.config`, `KOPIA_CACHE_DIRECTORY=/app/cache`, `KOPIA_LOG_DIR=/app/logs`, `KOPIA_PERSIST_CREDENTIALS_ON_CONNECT=false`, `KOPIA_CHECK_FOR_UPDATES=false` |
| A.2.7 | La imagen base es `ubuntu:jammy` fijado por digest |
| A.2.8 | Instala `fuse3`, `curl`, `sshfs`, `ca-certificates`, `tzdata` y el binario de `rclone` |

### A.3 Comandos de la CLI

Verificados contra la documentación oficial y contra el **código fuente** en
`cli/`:

| # | Comando verificado | Fuente |
|---|---|---|
| A.3.1 | `kopia repository create filesystem --path=` | [Repositories](https://kopia.io/docs/repositories/) |
| A.3.2 | `kopia repository create s3 --bucket= --access-key= --secret-access-key= [--endpoint= --region=]` | [Repositories](https://kopia.io/docs/repositories/) |
| A.3.3 | `kopia repository create azure --container= --storage-account= --storage-key=\|--sas-token=` | Ídem |
| A.3.4 | `kopia repository create b2 --bucket= --key-id= --key=` | Ídem |
| A.3.5 | `kopia repository create gcs --bucket= [--credentials-file=]` | Ídem |
| A.3.6 | `kopia repository create webdav --url= --webdav-username= --webdav-password=` | Ídem |
| A.3.7 | `kopia repository create sftp --path= --host= --username= --sftp-password=\|--keyfile=` | Ídem |
| A.3.8 | `kopia repository connect server --url= --server-cert-fingerprint= --server-username= --server-password=` | [Repository Server](https://kopia.io/docs/repository-server/) |
| A.3.9 | `kopia snapshot create <ruta>` | [Getting started](https://kopia.io/docs/getting-started/) |
| A.3.10 | `kopia snapshot list [--all] [<ruta>]` y que admite `--json` | `cli/command_snapshot_list.go` |
| A.3.11 | `kopia snapshot restore <id> [<destino>]` | [Getting started](https://kopia.io/docs/getting-started/) |
| A.3.12 | `kopia mount <id\|all> <punto>` y `kopia mount --webdav` | [Mounting](https://kopia.io/docs/mounting/) |
| A.3.13 | `kopia policy set --global --keep-latest/--keep-hourly/--keep-daily/--keep-weekly/--keep-monthly/--keep-annual/--compression=` | [Getting started](https://kopia.io/docs/getting-started/) |
| A.3.14 | `kopia policy export --to-file` / `kopia policy import --from-file` | Ídem |
| A.3.15 | `kopia server user add/list/set/delete` | [Repository Server](https://kopia.io/docs/repository-server/) |
| A.3.16 | `kopia server acl enable/list/add/remove` | Ídem |
| A.3.17 | `kopia server refresh` | Ídem |
| A.3.18 | `kopia maintenance info/set/run` | [Maintenance](https://kopia.io/docs/advanced/maintenance/) |
| A.3.19 | `kopia repository change-password` | [FAQ](https://kopia.io/docs/faqs/) |
| A.3.20 | `kopia cache info/clear/set` | [Getting started](https://kopia.io/docs/getting-started/) |

### A.4 Verificación de integridad — el núcleo del servicio

| # | Verificado | Fuente |
|---|---|---|
| A.4.1 | `kopia snapshot verify` existe y acepta `--sources=` | `cli/command_snapshot_verify.go` |
| A.4.2 | Acepta `--verify-files-percent=` (float 0.0–100.0), default 0 | Ídem |
| A.4.3 | Acepta `--file-parallelism=` (default: número de CPUs), `--file-queue-length=` (default 20000), `--max-errors=` (default 0) | Ídem |
| A.4.4 | `--all-sources` y `--parallel` están **deprecadas** y sin efecto. El kit no las usa | Ídem |
| A.4.5 | `snapshot verify` **no descarga** los blobs; `--verify-files-percent` **sí** (descarga, descifra y descomprime) | [Consistency](https://kopia.io/docs/advanced/consistency/) |
| A.4.6 | Upstream recomienda 100% mensual y al menos 1% diario (~98% anual) | Ídem |
| A.4.7 | "The gold standard [...] is to simply restore the snapshot" | Ídem |

### A.5 Server y banderas de seguridad

Leído de `cli/command_server_start.go` y `cli/command_server.go`:

| # | Verificado |
|---|---|
| A.5.1 | `--address` tiene default `http://127.0.0.1:51515` |
| A.5.2 | `--server-username` (default `kopia`) y `--server-password` leen `KOPIA_SERVER_USERNAME` / `KOPIA_SERVER_PASSWORD` |
| A.5.3 | `--server-control-username` (default `server-control`) lee `KOPIA_SERVER_CONTROL_PASSWORD` |
| A.5.4 | `kopia server status` existe y consulta `control/sources`; usa `serverClientFlags`, que lee las mismas variables de entorno |
| A.5.5 | **`--insecure` está oculto** y su ayuda dice *"Allow insecure configurations (do not use in production)"* |
| A.5.6 | **`--disable-csrf-token-checks` está oculto** y el comentario del código dice *"used for development/debugging only"* |
| A.5.7 | El compose oficial de upstream usa `--disable-csrf-token-checks`, `privileged: true`, `SYS_ADMIN`, `apparmor:unconfined` y `/dev/fuse`. El kit **no** replica eso |
| A.5.8 | La restricción de bind a loopback solo aplica cuando se combina `--insecure` **y** `--without-password`. Como el kit fija contraseña, no aplica. Ver `internal/insecureserverbind/insecureserverbind.go` |
| A.5.9 | El endpoint `/metrics` (Prometheus) se registra **sin autenticación**: *"init prometheus after adding interceptors that require credentials, so that this handler can be called without auth"* |
| A.5.10 | Con GRPC, `--insecure` no funciona: *"GRPC needs TLS"*, según la guía de Repository Server |
| A.5.11 | `--server-cert-fingerprint` acepta el formato SHA256 sin dos puntos |

### A.6 Reglas de negocio y límites

| # | Verificado | Fuente |
|---|---|---|
| A.6.1 | Cifrado por defecto: `AES256-GCM-HMAC-SHA256`. Alternativa: `CHACHA20-POLY1305-HMAC-SHA256` | [FAQ](https://kopia.io/docs/faqs/) |
| A.6.2 | El algoritmo de cifrado **no se puede cambiar** después de crear el repositorio | Ídem |
| A.6.3 | Sin la contraseña **no hay recuperación absoluta** | [Getting started](https://kopia.io/docs/getting-started/) |
| A.6.4 | `repository change-password` **exige estar conectado** | [FAQ](https://kopia.io/docs/faqs/) |
| A.6.5 | Compresión **desactivada** por defecto; `zstd` es de los recomendados | Ídem |
| A.6.6 | Mantenimiento rápido ~cada hora, completo cada 24 h, ambos por defecto | [Maintenance](https://kopia.io/docs/advanced/maintenance/) |
| A.6.7 | El mantenimiento completo **no es inmediato**: *"may take several hours and/or multiple maintenance cycles"* | Ídem |
| A.6.8 | Solo el propietario del mantenimiento lo ejecuta | Ídem |
| A.6.9 | `--safety=none` puede introducir corrupción | Ídem |
| A.6.10 | Cachés por defecto: 5000 MB de contenido y 5000 MB de metadatos | `cli/command_repository_connect.go` |
| A.6.11 | Object Lock: **sí** en S3, Azure y GCS. **No** en el motor `b2` nativo (hay que usar el motor `s3` con `--endpoint`) | [Ransomware](https://kopia.io/docs/advanced/ransomware/) |
| A.6.12 | `kopia maintenance set --extend-object-locks true` renueva las fechas de retención | Ídem |
| A.6.13 | El `full-interval` debe ser **al menos un día más corto** que el `retention-period` | Ídem |
| A.6.14 | Kopia **nunca borra de verdad** del almacenamiento: pone una marca `hidden`; el borrado real lo hace Lifecycle Management | Ídem |
| A.6.15 | En Repository Server solo se controlan **manifiestos**, no el contenido | [Repository Server](https://kopia.io/docs/repository-server/) |
| A.6.16 | Las credenciales de usuario tardan **5–10 minutos** en aplicarse | Ídem |
| A.6.17 | `rclone` y `gdrive` están marcados **experimentales** por upstream | [Repositories](https://kopia.io/docs/repositories/) |

### A.7 Lo que NO se pudo verificar

| # | Pendiente de verificación documental |
|---|---|
| A.7.1 | Comportamiento exacto del proxy de Coolify/Traefik con gRPC sobre este servicio |
| A.7.2 | Requisitos oficiales de memoria y disco: **upstream no los pública**. No se inventaron |
| A.7.3 | Ruta interna donde Coolify deja los certificados TLS para montarlos |

---

## Parte B — Pendiente de ejecución

**Nada de esto se ejecutó.** Es el trabajo que hay que hacer antes de ofrecer
el servicio a un cliente.

### B.1 Despliegue básico

| # | Prueba | Cómo | Resultado esperado |
|---|---|---|---|
| B.1.1 | El compose levanta en un servidor limpio | `docker compose up -d` | Contenedor arriba |
| B.1.2 | El healthcheck pasa | `docker compose ps` | `healthy` en menos de 90 s |
| B.1.3 | El puerto NO está expuesto a internet | `ss -ltnp \| grep 51515` desde otra máquina | Sin conexión |
| B.1.4 | El contenedor corre sin privilegios | `docker inspect --format '{{.HostConfig.Privileged}}'` | `false` |
| B.1.5 | Los volúmenes se crean con el nombre fijo | `docker volume ls` | `hefesto-kopia-config`, `hefesto-kopia-cache`, `hefesto-kopia-logs` |
| B.1.5b | **`lib.sh` y el servidor usan los MISMOS volúmenes** | `docker volume ls` + revisar el montaje de un `docker run` de `lib.sh` | Mismo volumen, no dos distintos |
| B.1.6 | Reinicio automático | `docker compose down && docker compose up -d` | El repositorio sigue accesible |

### B.2 Creación de repositorio

| # | Prueba | Resultado esperado |
|---|---|---|
| B.2.1 | `crear-repositorio.sh` crea el repo sobre S3 | Mensaje de éxito |
| B.2.2 | El script **no pisa** un repositorio existente | Sale con aviso, sin cambios |
| B.2.3 | Detecta y rechaza `KOPIA_PASSWORD` de ejemplo | Falla con mensaje claro |
| B.2.4 | La política global queda aplicada | `kopia policy show --global` |
| B.2.5 | El propietario del mantenimiento queda designado | `kopia maintenance info` muestra ese owner |
| B.2.6 | El resumen se escribe **sin secretos** | `manifiestos/repositorio-*.resumen.txt` |

### B.3 Respaldo

| # | Prueba | Resultado esperado |
|---|---|---|
| B.3.1 | `respaldar.sh` toma una instantánea | Instantánea creada |
| B.3.2 | Deja manifiesto JSON con el ID de la instantánea | ID no vacío |
| B.3.3 | El SHA-256 del manifiesto es correcto | `sha256sum -c` pasa |
| B.3.4 | La marca `.completo` aparece **solo** al final | Existe tras el éxito |
| B.3.5 | Un fallo **no** deja marca `.completo` | Queda `.en-proceso` |
| B.3.6 | `--pausar`/`--reanudar` reanuda aunque el respaldo falle | Contenedor levantado igual |
| B.3.7 | Ruta inexistente → falla con mensaje claro | No hay `.completo` |
| B.3.8 | Ruta relativa → rechazada | No hay `.completo` |

### B.4 Verificación

| # | Prueba | Resultado esperado |
|---|---|---|
| B.4.1 | `verificar.sh --porcentaje 0` sobre un repo sano | Código de salida `0` |
| B.4.2 | `verificar.sh --porcentaje 100` | Código `0`, descarga todo |
| B.4.3 | El código de salida es `1` ante corrupción | Simular daño y comprobar |
| B.4.4 | `--porcentaje` fuera de rango → código `2` | Rechazo |
| B.4.5 | Sin repositorio conectado → código `3` | Rechazo |

### B.5 Restauración

| # | Prueba | Resultado esperado |
|---|---|---|
| B.5.1 | `restaurar.sh --listar` muestra instantáneas | Listado |
| B.5.2 | Restaura a un directorio nuevo | Archivos íntegros |
| B.5.3 | **Rechaza** un destino con datos | Sale con código `1` y explica |
| B.5.4 | Acepta con `--force` | Restaura encima |
| B.5.5 | Rechaza destino `/`, `/etc`, `/var` | Rechazo |
| B.5.6 | Rechaza ruta relativa | Rechazo |
| B.5.7 | Rechaza destino con `..` | Rechazo |
| B.5.8 | Rechaza destino symlink | Rechazo |
| B.5.9 | Con `--servidor`, el servicio queda **detenido** | Estado verificado |
| B.5.10 | Deja muestreo de SHA-256 | Archivo generado |
| B.5.11 | Los archivos restaurados coinciden byte a byte | `diff` sin diferencias |

### B.6 Recuperación desde cero

| # | Prueba | Resultado esperado |
|---|---|---|
| B.6.1 | Instalar en una máquina virtual **nueva** | Kopia operativo |
| B.6.2 | Conectar solo con bucket + contraseña | Conecta |
| B.6.3 | `snapshot list --all` muestra las instantáneas | Listado completo |
| B.6.4 | Verificación al 100% | Código `0` |
| B.6.5 | Restaurar un árbol completo | Datos íntegros |
| B.6.6 | Repetir con `--override-hostname` correcto | Las instantáneas viejas aparecen |

> **B.6 es la prueba que define el servicio.** Sin ella, el producto es una
> promesa.

### B.7 Operación y riesgos

| # | Prueba | Resultado esperado |
|---|---|---|
| B.7.1 | Apagar el propietario del mantenimiento | Se deja de purgar (comportamiento documentado) |
| B.7.2 | Conectar un cliente con hostname cambiado **sin** `--override` | Origen nuevo sin historial: documentado |
| B.7.3 | Conectar **con** `--override` | El historial se conserva |
| B.7.4 | Medir RAM y CPU con 10–50 GB de datos | Números reales para dimensionar |
| B.7.5 | Bucket con clave sin permiso de borrado | El mantenimiento sigue funcionando |
| B.7.6 | Object Lock con `retention-period=30d` | Retención activa y renovable |
| B.7.7 | Medir cuánto tarda una verificación al 100% | Para fijar el SLA |
| B.7.8 | Pruebas con Coolify y dominio real | gRPC funciona tras el proxy |
| B.7.9 | Confirmar que `/metrics` no es alcanzable desde fuera | Solo loopback |

### B.8 Seguridad

| # | Prueba | Resultado esperado |
|---|---|---|
| B.8.1 | `grep -r` de secretos en el kit | Solo `.env` (ignorado por git) |
| B.8.2 | Sin secretos en `.env.example` | Confirmado |
| B.8.3 | La UI exige autenticación | Login obligatorio |
| B.8.4 | Las credenciales del bucket no están en el contenedor | Solo en el `.env` |
| B.8.5 | `docker inspect` no filtra secretos en el healthcheck | Confirmado por diseño |

---

## Parte C — Declaraciones de honestidad

- **No se ejecutó Docker.** No hay evidencia de ejecución en este kit.
- **No se creó ningún repositorio de prueba.** No hay instantáneas de prueba.
- **Las versiones y digests sí están verificados**, contra la API oficial.
- **Los comandos sí están verificados**, contra la documentación y el código
  fuente. El healthcheck y los flags de `server` se verificaron leyendo
  `cli/command_server_start.go`, no probando.
- **La única afirmación deliberadamente aproximada** es la memoria de 2 GB.
  Upstream no pública mínimos; es una recomendación de Hefesto, marcada como
  tal, y con medición pendiente (B.7.4).
- **Backends experimentales** (`rclone`, `gdrive`) quedaron fuera a propósito.
- **Ninguna prueba simulada se presenta como real.**

## Fuentes

- Documentación: <https://kopia.io/docs/>
- Código fuente: <https://github.com/kopia/kopia>
- Releases: <https://api.github.com/repos/kopia/kopia/releases>
- Docker Hub: <https://hub.docker.com/r/kopia/kopia>