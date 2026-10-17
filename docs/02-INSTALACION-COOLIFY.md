# 02 — Instalación en Coolify

Coolify despliega este kit como un recurso de tipo **Docker Compose**. Esta guía
cubre las diferencias con `docker compose` a secas, y explica qué hay que
configurar a mano porque el kit, por diseño, **no** expone el puerto.

**Estado: el flujo con Coolify NO se probó.** Es una guía construida sobre la
documentación de Kopia y sobre cómo funciona el proxy de Coolify. Marcá lo que
falta en `07-PRUEBAS-DE-ACEPTACION.md`.

---

## 0. ¿Sirve este kit para Coolify?

**Sí, con una advertencia importante.**

El modo **servidor de repositorios** es un servicio de larga duración, con
volumen persistente y estado. Es exactamente el tipo de cosa que Coolify maneja
bien.

La advertencia: Kopia Repository Server habla **HTTP + gRPC sobre el mismo
puerto**, y el cliente se conecta con gRPC. Por detrás de un proxy, hace falta
un certificado TLS. Upstream lo dice sin rodeos:

> *"you start your kopia server with a certificate (`--insecure` does not work,
> as GRPC needs TLS, which is used by Repository Server)"*
> — <https://kopia.io/docs/repository-server/#kopia-behind-a-reverse-proxy>

Su ejemplo de nginx usa `grpc_pass grpcs://` y `client_max_body_size 0`.
**Coolify y Traefik manejan gRPC automáticamente** cuando el backend usa TLS y
el cliente negocia h2. Hay que verificarlo en el primer despliegue.

---

## 1. Antes de crear el recurso

Resolvé estas preguntas:

| Pregunta | Por qué importa |
|---|---|
| ¿El bucket ya existe? | Kopia **no** crea ni paga almacenamiento. Tenés que crearlo antes. |
| ¿Ya creaste el repositorio con `crear-repositorio.sh`? | El servidor no arranca sin repositorio. |
| ¿Habrá clientes remotos? | Si no, alcanza con túnel SSH y te ahorrás el dominio. |

Si el repositorio **no** existe todavía, crealo en el servidor antes de crear
el recurso de Coolify:

```bash
cd ~/kits/hefesto-respaldo-kopia
cp .env.example .env && $EDITOR .env
chmod +x scripts/*.sh
./scripts/crear-repositorio.sh
```

---

## 2. Crear el recurso

En Coolify:

1. **New Resource → Docker Compose**
2. Nombre: `respaldos-kopia`
3. Repositorio: subí el kit, o pegá el contenido del `compose.yaml`.

### Variables de entorno

En la pestaña **Environment Variables** del recurso, cargá el `.env` completo.
Marcá `KOPIA_PASSWORD`, `KOPIA_SERVER_PASSWORD` y `KOPIA_SERVER_CONTROL_PASSWORD`
como **secretos** si Coolify te lo permite: así no aparecen en claro en la UI.

### Volúmenes

Coolify usa nombres de volumen con prefijo de proyecto. El `compose.yaml` ya
declara volúmenes **con nombre**, así que no hay que montar rutas del host a
mano.

Verificá después del despliegue:

```bash
docker volume ls | grep kopia
```

Persisten entre despliegues: eso es lo que no hay que perder.

---

## 3. Puerto

Por defecto el kit publica:

```yaml
ports:
  - "127.0.0.1:51515:51515"
```

En Coolify **no expongas el puerto**. Marcá la opción de proxy y configurá un
dominio. El puerto literal queda para diagnóstico local.

---

## 4. TLS y dominio

Dos caminos.

### Camino A — proxy de Coolify (recomendado)

1. Asigná un dominio, por ejemplo `respaldos.tuservidor.cl`.
2. Coolify emite el certificado automáticamente.
3. Activá el override de TLS en **Docker Compose Override**:

```yaml
services:
  kopia:
    volumes:
      - kopia-config:/app/config
      - kopia-cache:/app/cache
      - kopia-logs:/app/logs
      - ./config/tls:/app/config/tls:ro
    command:
      - server
      - start
      - --address=0.0.0.0:51515
      - --tls-cert-file=/app/config/tls/kopia.crt
      - --tls-key-file=/app/config/tls/kopia.key
```

Esto es lo mismo que `compose.tls.yaml`. Para que funcione tenés que poner el
certificado de Coolify en `config/tls/`. La ruta exacta de los certificados en
el host la define Coolify; copiálos o montá el directorio.

**Pendiente de verificar:** cómo inyecta Coolify exactamente sus certificados en
el contenedor. Hay que probarlo en un servidor real.

### Camino B — certificado autogenerado por Kopia

No depende de Coolify. Kopia genera su propio certificado en el primer
arranque y **imprime la huella**:

```
SERVER CERT SHA256: 48537cce585fed39fb26c639eb8ef38143592ba4b4e7677a84a31916398d40f7
```

Copiá esa huella a `KOPIA_TLS_FINGERPRINT` en el `.env`. Los clientes la usan
así:

```bash
kopia repository connect server \
  --url=https://respaldos.tuservidor.cl:51515 \
  --server-cert-fingerprint=48537cce585fed39fb26c639eb8ef38143592ba4b4e7677a84a31916398d40f7
```

Una huella de certificado **no es un secreto**: upstream la imprime en pantalla
justo para poder anotarla.

> **Dos advertencias de upstream.** (1) Sacá `--tls-generate-cert` después del
> primer arranque, si no el servidor falla al reiniciar. (2) El certificado por
> defecto se emite para `127.0.0.1` y dura 3650 días.

---

## 5. Healthcheck

El kit trae un healthcheck propio que usa `kopia server status` contra la API
de control. La imagen oficial de Kopia **no declara `HEALTHCHECK`** en su
Dockerfile, así que no hay un healthcheck oficial que copiar.

Coolify marca el servicio como `healthy` / `unhealthy` a partir del que declara
el compose. Para verlo:

```bash
docker inspect --format '{{.State.Health.Status}}' <contenedor>
docker inspect --format '{{json .State.Health.Log}}' <contenedor> | tail -c 800
```

El healthcheck usa las variables `KOPIA_SERVER_USERNAME` y
`KOPIA_SERVER_PASSWORD`, que ya están en el entorno del contenedor. **No hay
ningún secreto escrito dentro del comando**, así que `docker inspect` no lo
filtra.

> **Costo real del healthcheck:** `kopia server status` consulta
> `control/sources` y lista los orígenes del repositorio. Con muchos orígenes
> no es trivial. Por eso el intervalo es de 60 segundos y no de 10. Si tenés
> decenas de fuentes, subilo a 120 s.

---

## 6. Banderas que **NO** activamos, y por qué

El `docker-compose.yml` oficial de Kopia incluye `--disable-csrf-token-checks`.
Este kit **no lo usa**, a propósito.

Mirando el código fuente (`cli/command_server_start.go`), ese flag está
declarado como **oculto** y el comentario del struct dice:

```go
disableCSRFTokenChecks bool // disable CSRF token checks - used for
                          // development/debugging only
```

Lo mismo con `--insecure`, cuya ayuda oficial es:

> *"Allow insecure configurations (do not use in production)"*

El compose de upstream es un ejemplo de estación de trabajo: corre como root,
con `privileged: true`, `SYS_ADMIN`, `apparmor:unconfined` y `/dev/fuse`. **Eso
no es un despliegue de producción**, es lo mínimo para poder usar `kopia mount`
en el navegador.

Este kit corre sin privilegios, en loopback, con contraseña, y sin esas
banderas.

Si en algún momento necesitás `kopia mount` **dentro** del contenedor, eso sí
requiere privileges adicionales. Se documenta en
`05-RESPALDOS-Y-RESTAURACION.md`, y no forma parte del compose por defecto.

---

## 7. Verificar el despliegue

```bash
docker compose ps                          # healthy
docker compose logs --tail=50 kopia
curl -k https://respaldos.tuservidor.cl:51515/ | head -20
```

Y después, desde un cliente:

```bash
kopia repository connect server --url=... --server-cert-fingerprint=...
kopia snapshot list --all
```

Si `snapshot list` no muestra nada, el usuario no existe o el servidor tiene
cacheadas credenciales viejas. Upstream avisa que los cambios de credenciales
tardan **5 a 10 minutos** en aplicarse; para forzar:

```bash
docker compose exec kopia /bin/kopia server refresh \
  --address=https://127.0.0.1:51515 \
  --server-cert-fingerprint=$HUELLA
```

---

## 8. Coolify vs. `docker compose` directo

| Tema | Coolify | `docker compose` |
|---|---|---|
| Volúmenes | Con prefijo de proyecto, declarados en el compose | Idéntico |
| TLS | Lo gestiona Coolify, hay que inyectarlo | Lo genera Kopia o lo aporta tu CA |
| gRPC | Traefik lo negocia, **verificar** | nginx con `grpc_pass` |
| Healthcheck | Lo lee del compose | Idéntico |
| Reinicio tras caída del owner | Coolify reinicia el contenedor | Requiere systemd o supervisor |

**Recomendación de Hefesto:** para la primera instalación de un cliente, usar
`docker compose` directo con `compose.tls.yaml`. Para operaciones donde ya haya
un Coolify funcionando, el recurso Docker Compose es cómodo.

---

## 9. Common issues

| Síntoma | Causa | Solución |
|---|---|---|
| El contenedor reinicia en bucle | No hay repositorio creado | `crear-repositorio.sh` antes del primer `up` |
| `unhealthy` desde el arranque | Credenciales de la API mal | Revisá `KOPIA_SERVER_*` |
| El cliente no conecta por gRPC | Falta TLS en el backend | Aplicá `compose.tls.yaml` |
| El cliente conecta pero no ve instantáneas | Credenciales cacheadas | `kopia server refresh` o reiniciá |
| El proxy corta la subida | Límite de tamaño de cuerpo | Verificá que el proxy no imponga `client_max_body_size` |

## Fuentes

- Repository Server y proxy inverso: <https://kopia.io/docs/repository-server/>
- Código fuente (`cli/command_server_start.go`,
  `cli/command_server.go`): <https://github.com/kopia/kopia/tree/master/cli>
- Dockerfile oficial: <https://github.com/kopia/kopia/blob/master/tools/docker/Dockerfile>
- Compose oficial de upstream: <https://github.com/kopia/kopia/blob/master/tools/docker/docker-compose.yml>