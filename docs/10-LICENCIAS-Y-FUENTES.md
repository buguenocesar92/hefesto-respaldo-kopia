# 10 — Licencias y fuentes

Este documento es el índice de fuentes de todo el kit. Cada afirmación técnica
que aparece en la documentación tiene un respaldo verificable acá.

---

## 1. Licencia del componente principal

### Kopia

| Dato | Valor |
|---|---|
| Software | Kopia |
| Licencia | **Apache License 2.0** |
| SPDX | `Apache-2.0` |
| Sitio | <https://kopia.io> |
| Código | <https://github.com/kopia/kopia> |
| Texto legal | <https://www.apache.org/licenses/LICENSE-2.0> |

**Cómo se verificó:** `api.github.com/repos/kopia/kopia` → campo
`license.spdx_id` → `Apache-2.0`.

### Qué significa Apache-2.0 en la práctica

**Se puede vender, modificar y redistribuir comercialmente.** No hay copyleft.

Obligaciones reales:

1. **Atribución**: hay que indicar que Kopia es obra de sus autores y nombrar
   la licencia Apache-2.0.
2. **Notices**: respetar los avisos de patente y marcas que incluya el código.
3. **Estado de cambios**: si se modifica el código, hay que indicarlo.
   **Este kit no modifica el código de Kopia**, así que hoy no aplica.
4. **Sin garantía**: se distribuye "AS IS".

Detalle completo en `LICENCIAS.md`.

### Atribución mínima para la entrega

```
Respaldo gestionado con Kopia (https://kopia.io)
Kopia está bajo licencia Apache License 2.0.
Copyright (c) los autores de Kopia.

Operación y gestión de respaldos: Hefesto Studio.
```

---

## 2. Imagen Docker

| Dato | Valor |
|---|---|
| Imagen | `kopia/kopia` en Docker Hub |
| Licencia | Apache-2.0 (mismo proyecto) |
| Dockerfile | <https://github.com/kopia/kopia/blob/master/tools/docker/Dockerfile> |
| Compose de ejemplo | <https://github.com/kopia/kopia/blob/master/tools/docker/docker-compose.yml> |

### Lo que el Dockerfile define (leído directamente)

```dockerfile
FROM ubuntu:jammy@sha256:b1066385161d28ddf6bc7e7b28a9170eec11484c821d1a5150d176cbde41d7f7
ENV KOPIA_CONFIG_PATH=/app/config/repository.config
ENV KOPIA_LOG_DIR=/app/logs
ENV KOPIA_CACHE_DIRECTORY=/app/cache
ENV RCLONE_CONFIG=/app/rclone/rclone.conf
ENV KOPIA_PERSIST_CREDENTIALS_ON_CONNECT=false
ENV KOPIA_CHECK_FOR_UPDATES=false
WORKDIR /app
ENTRYPOINT ["/bin/kopia"]
```

Paquetes instalados: `fuse3`, `ca-certificates`, `curl`, `tzdata`, `sshfs`, más
los binarios de `kopia` y `rclone`.

---

## 3. Versión fijada

| Dato | Valor |
|---|---|
| Versión | **v0.23.1** |
| Publicada | 2026-06-16 |
| Digest del índice | `sha256:89fd95ee2942880ca00eae964266958a394421ddbdf69bca62e38afc55f5900e` |
| amd64 | `sha256:83d8bc7bce313dd8b2c17771b5f3f804e18e79ad7d7cc6bc994ff5872374794d` |
| arm64 | `sha256:df0c8a203511eb4dfe985a5e189dc74d542c2eb72ce5006b2ba021edb5c4cd5f` |
| arm (v7) | `sha256:ecd02b7b81004b72c523a09ffe2db098e7038a046ef352fc5337763f7d24520b` |

Procedimiento de verificación y actualización: `VERSION.md`.

---

## 4. Dependencias y software de terceros

| Componente | Licencia | Rol |
|---|---|---|
| Ubuntu Jammy (imagen base) | Licencias de Ubuntu | Sistema operativo de la imagen |
| rclone | MIT y GPL-3.0 según el componente | Almacenamiento vía rclone (**experimental** en Kopia) |
| Go (lenguaje) | BSD-3-Clause | En el que está escrito Kopia |
| fuse3 | LGPL-2.1 | Montaje de instantáneas |
| curl | curl (libcurl) | Herramienta de línea de comandos |
| OpenSSH / sshfs | BSD | Acceso SFTP |

> **Alcance de la verificación:** no auditamos componente por componente el
> árbol de dependencias de Kopia. La responsabilidad asumida es que el proyecto
> completo se distribuye bajo Apache-2.0. Para una auditoría de nivel
> corporativo, hay que revisar el `go.mod` del proyecto.

---

## 5. Licencias de Hefesto

Los archivos propios del kit (`scripts/`, `compose.yaml`, `compose.tls.yaml`,
`docs/`, ejemplos) son **propiedad de Hefesto Studio** y **no son copyleft**.

Se pueden entregar bajo la licencia que Hefesto defina.

---

## 6. Índice de fuentes del kit

Todo lo afirmado en este kit sale de acá. Si algo no está en esta lista, se
trata como pendiente de verificación.

### Documentación oficial

| Tema | URL |
|---|---|
| Inicio rápido | <https://kopia.io/docs/getting-started/> |
| FAQ (cifrado, compresión, contraseña, CPU/RAM) | <https://kopia.io/docs/faqs/> |
| Almacenamientos soportados | <https://kopia.io/docs/repositories/> |
| Repository Server, usuarios, ACL, proxy inverso | <https://kopia.io/docs/repository-server/> |
| Verificación de integridad y corrupción | <https://kopia.io/docs/advanced/consistency/> |
| Mantenimiento | <https://kopia.io/docs/advanced/maintenance/> |
| Protección contra ransomware | <https://kopia.io/docs/advanced/ransomware/> |
| Montar instantáneas | <https://kopia.io/docs/mounting/> |
| Releases | <https://github.com/kopia/kopia/releases> |
| Licencia | <https://www.apache.org/licenses/LICENSE-2.0> |

### Código fuente (verificación de banderas y comandos)

Los scripts del kit usan comandos y banderas que se verificaron **leyendo el
código**, no solo la documentación. Eso importa porque varias banderas que
upstream muestra en ejemplos son **ocultas** y solo de desarrollo.

| Archivo | Qué se verificó |
|---|---|
| `cli/command_server_start.go` | Banderas de `server start`, incluida `--insecure` y `--disable-csrf-token-checks` marcadas como ocultas; autenticadores; endpoint `/metrics` sin auth |
| `cli/command_server.go` | Default de `--address`, `--server-username`, `--server-password`, `--server-cert-fingerprint`, aliases ocultos del cliente |
| `cli/command_server_status.go` | Existencia y comportamiento de `kopia server status` |
| `cli/command_snapshot_verify.go` | Banderas de `snapshot verify`, rangos y deprecaciones |
| `cli/command_snapshot_list.go` | `snapshot list`, alias `ls`, y el flag `--json` |
| `cli/command_repository_connect.go` | `--override-hostname`, `--override-username`, cachés por defecto de 5000 MB |
| `internal/insecureserverbind/insecureserverbind.go` | Cuándo se aplica la restricción de bind a loopback |
| `tools/docker/Dockerfile` | Entry point, variables de entorno, ausencia de `HEALTHCHECK` |

Repositorio: <https://github.com/kopia/kopia/tree/master>

### Docker Hub

| Dato | URL |
|---|---|
| Imagen | <https://hub.docker.com/r/kopia/kopia> |
| Digest de la versión | <https://hub.docker.com/v2/repositories/kopia/kopia/tags/0.23.1> |

---

## 7. Declaraciones que upstream no hace

Para que conste, y para no inventar:

| Dato | Estado |
|---|---|
| Requisitos mínimos de RAM | **Upstream no los pública.** La cifra de 2 GB es recomendación de Hefesto |
| Requisitos mínimos de disco | **Upstream no los pública.** Ver `05-RESPALDOS-Y-RESTAURACION.md` |
| Costo de almacenamiento | **Upstream no pública precios.** Varían por proveedor y región |
| SLA | **No existe.** Kopia se distribuye sin garantía |
| Cumplimiento normativo | **No auditado.** Ninguna certificación |
| Formato de exportación estándar | **No existe.** La única salida es restaurar |
| Integración con ERP o base de datos | **No existe.** Kopia no tiene conectores |

---

## 8. Nota sobre Supabase

Este kit **no usa Supabase ni ningún motor de base de datos relacional**.
Kopia no tiene base de datos: respalda archivos.

Si algún documento de Hefesto vincula este kit con Supabase, es un error: la
combinación no aplica. Para respaldo de datos de una base PostgreSQL
administrada por Supabase habría que respaldar el **volcado** de la base, que es
un tema distinto y queda fuera de este kit.

## Fuentes

- Apache-2.0: <https://www.apache.org/licenses/LICENSE-2.0>
- SPDX de Kopia: `api.github.com/repos/kopia/kopia` → `license.spdx_id`
- Licencias por componente: `LICENCIAS.md` de este kit
- Verificación de versión: `VERSION.md` de este kit
- Pruebas y pendientes: `07-PRUEBAS-DE-ACEPTACION.md` de este kit