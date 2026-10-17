# VERSION.md — Hefesto Studio, kit de respaldo Kopia

Este documento fija **exactamente** qué versión se despliega y de dónde sale ese
número. Todo lo que aparece acá fue verificado contra la fuente oficial; la
fecha de verificación está escrita.

---

## 1. Versión de Kopia

| Dato | Valor | Fuente de la verificación |
|---|---|---|
| Versión estable fijada | **v0.23.1** | `api.github.com/repos/kopia/kopia/releases` |
| Fecha de publicación | **2026-06-16** (GitHub) / **2026-06-16T01:32:08Z** (Docker Hub) | Docker Hub API |
| Imagen oficial | `kopia/kopia` | Docker Hub |
| Licencia | **Apache-2.0** (`spdx_id: Apache-2.0`) | API de GitHub |
| Estrellas del repositorio | 14 365 (al verificar) | API de GitHub |

### Cómo se verificó

```powershell
Invoke-RestMethod 'https://api.github.com/repos/kopia/kopia/releases?per_page=3'
# REL: v0.23.1 | 2026-06-16T01:27:33Z | prerelease=False | draft=False
# REL: v0.23.0 | 2026-05-12T00:08:06Z | prerelease=False | draft=False
# REL: v0.22.3 | 2025-12-02T06:37:52Z | prerelease=False | draft=False
```

**v0.23.1 es la última versión estable: no es prerelease ni borrador.**
Verificácalo vos mismo antes de actualizar el kit:
<https://github.com/kopia/kopia/releases/latest>

### Por qué v0.23.1 y no v0.23.0

v0.23.1 es una **corrección de errores que arregla una condición de carrera
poco común capaz de provocar pérdida de datos**, y upstream recomienda
actualizar. Un kit de respaldo que fija una versión con un fallo conocido de
pérdida de datos sería incoherente. Detalle en las notas de la versión:
<https://github.com/kopia/kopia/releases/tag/v0.23.1>

---

## 2. Fijado por digest (no solo por etiqueta)

En `compose.yaml` la imagen está fijada **por etiqueta y por digest**:

```yaml
image: kopia/kopia:0.23.1@sha256:89fd95ee2942880ca00eae964266958a394421ddbdf69bca62e38afc55f5900e
```

- El **digest** es el índice multiplataforma publicado por Docker Hub.
- Esto cumple la regla del contrato: nunca `:latest`.
- Verificación reproducible:

```powershell
$t = Invoke-RestMethod 'https://hub.docker.com/v2/repositories/kopia/kopia/tags/0.23.1'
$t.digest
# sha256:89fd95ee2942880ca00eae964266958a394421ddbdf69bca62e38afc55f5900e
```

### Digests por plataforma (v0.23.1)

| Plataforma | Digest |
|---|---|
| índice multiplataforma | `sha256:89fd95ee2942880ca00eae964266958a394421ddbdf69bca62e38afc55f5900e` |
| linux/amd64 | `sha256:83d8bc7bce313dd8b2c17771b5f3f804e18e79ad7d7cc6bc994ff5872374794d` |
| linux/arm64 | `sha256:df0c8a203511eb4dfe985a5e189dc74d542c2eb72ce5006b2ba021edb5c4cd5f` |
| linux/arm (v7) | `sha256:ecd02b7b81004b72c523a09ffe2db098e7038a046ef352fc5337763f7d24520b` |

---

## 3. Imagen base de la imagen oficial

Leída desde `tools/docker/Dockerfile` en el repositorio de Kopia
(<https://github.com/kopia/kopia/blob/master/tools/docker/Dockerfile>):

```dockerfile
FROM ubuntu:jammy@sha256:b1066385161d28ddf6bc7e7b28a9170eec11484c821d1a5150d176cbde41d7f7
ENTRYPOINT ["/bin/kopia"]
WORKDIR /app
```

Consecuencias que el kit respeta:

- El entrypoint **es** el binario de kopia. Por eso en `compose.yaml` el
  `command:` empieza en `server`, no en `kopia server`.
- El Dockerfile **no** declara `USER`, así que el proceso corre como root.
  El kit **no** sobrescribe el usuario para no apartarse de upstream.
- El Dockerfile **no** declara `EXPOSE` ni `HEALTHCHECK`. No hay healthcheck
  oficial que copiar: el del kit es propio y está justificado en
  `docs/07-PRUEBAS-DE-ACEPTACION.md`.
- Variables de entorno que la imagen ya define (no hay que declararlas):

  | Variable | Valor en la imagen |
  |---|---|
  | `KOPIA_CONFIG_PATH` | `/app/config/repository.config` |
  | `KOPIA_CACHE_DIRECTORY` | `/app/cache` |
  | `KOPIA_LOG_DIR` | `/app/logs` |
  | `KOPIA_PERSIST_CREDENTIALS_ON_CONNECT` | `false` |
  | `KOPIA_CHECK_FOR_UPDATES` | `false` |
  | `RCLONE_CONFIG` | `/app/rclone/rclone.conf` |

  Por eso el kit monta `/app/config`, `/app/cache` y `/app/logs`.

- La imagen incluye `curl`, `fuse3`, `sshfs` y `rclone`. `fuse3` es lo que
  permite `kopia mount` (FUSE) **si** se agrega `/dev/fuse` y `SYS_ADMIN`; el
  compose por defecto **no** lo hace. Ver `docs/05-RESPALDOS-Y-RESTAURACION.md`.

---

## 4. Versión del kit

| Componente | Versión |
|---|---|
| Kit Hefesto `hefesto-respaldo-kopia` | **1.0.0** |
| Kopia | **v0.23.1** (fijada por digest) |
| Docker Compose | formato `compose.yaml` sin la clave `version:` obsoleta |

El kit no incluye código de la aplicación: es una composición, scripts de
operación y documentación alrededor de la imagen oficial. Ver `README.md`,
sección «Qué es y qué no es este kit».

---

## 5. Cómo actualizar a una versión nueva

1. Leé las notas de la versión: <https://github.com/kopia/kopia/releases>.
2. Resolvé el digest nuevo:

   ```powershell
   $t = Invoke-RestMethod 'https://hub.docker.com/v2/repositories/kopia/kopia/tags/<VERSION>'
   $t.digest
   ```

3. Actualizá `VERSION.md` y la línea `image:` de `compose.yaml`.
4. Seguí el procedimiento de `docs/06-ACTUALIZACIONES-Y-REVERSION.md`,
   que incluye verificar el repositorio **antes y después**.

Nunca pruebes una versión nueva directamente sobre el repositorio de un
cliente. Cloná el repositorio a uno de prueba primero.