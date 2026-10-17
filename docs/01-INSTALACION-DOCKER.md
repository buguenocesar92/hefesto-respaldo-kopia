# 01 — Instalación con Docker (servidor Ubuntu/Debian limpio)

Procedimiento paso a paso, desde una máquina recién estrenada hasta el primer
respaldo verificado.

**Estado: este procedimiento NO se ejecutó en el entorno donde se construyó el
kit.** Es una guía escrita contra la documentación oficial de Kopia y el
Dockerfile del proyecto. Marcá cada paso en `07-PRUEBAS-DE-ACEPTACION.md` a
medida que lo verifiques en un servidor real.

---

## 0. Requisitos previos

| Requisito | Detalle |
|---|---|
| Sistema | Ubuntu 22.04 / 24.04 o Debian 12 |
| Docker Engine | Con el plugin **Compose v2** (`docker compose`, no `docker-compose`) |
| Almacenamiento | Un bucket, NAS o disco **ya creado y pagado por vos**. Kopia no lo provisiona. |
| Puertos | Salida a internet. **No** hay que abrir nada entrante si el puerto queda en loopback. |

Sobre la memoria: upstream **no publica requisitos mínimos oficiales**. En la
práctica 2 GB de RAM alcanzan para el servidor de repositorios de una Pyme.
Es una recomendación de Hefesto, medida pendiente de confirmar con datos
reales (`docs/07-PRUEBAS-DE-ACEPTACION.md`).

---

## 1. Preparar el servidor

```bash
# Actualizar
sudo apt-get update && sudo apt-get upgrade -y

# Herramientas básicas
sudo apt-get install -y curl ca-certificates openssl git

# Usuario para las operaciones de Docker (evita usar root)
sudo adduser --disabled-password --gecos "" hefesto
sudo usermod -aG docker hefesto
newgrp docker        # o cerrá la sesión y volvé a entrar
```

> ⚠️ Quien esté en el grupo `docker` tiene, en la práctica, **control total
> sobre el servidor**: puede montar el sistema de archivos raíz del host.
> En un VPS de producción, evaluá si eso es aceptable para tu equipo.

## 2. Instalar Docker

Seguí la guía oficial de Docker para tu distribución:
<https://docs.docker.com/engine/install/ubuntu/>

Verificá:

```bash
docker --version
docker compose version
docker run --rm hello-world
```

## 3. Copiar el kit

```bash
mkdir -p ~/kits && cd ~/kits
# copiá el kit acá (scp, git, lo que prefieras)
cd hefesto-respaldo-kopia

chmod +x scripts/*.sh
```

El permiso de ejecución no siempre sobrevive al copiado desde Windows o desde
un volumen sin soporte de bits de Unix.

## 4. Configurar el `.env`

```bash
cp .env.example .env
chmod 600 .env          # contiene la clave del repositorio
```

Generá los secretos. **Nunca los escribas a mano ni los pegues en un chat:**

```bash
# Clave del repositorio (la importante)
openssl rand -base64 48 | tr -d '\n=' ; echo

# Contraseñas de la interfaz y del control
openssl rand -base64 32 | tr -d '\n=' ; echo
openssl rand -base64 32 | tr -d '\n=' ; echo
```

Editá `.env` y completá, como mínimo:

```dotenv
KOPIA_PASSWORD=<clave generada>
KOPIA_SERVER_USERNAME=admin-respaldos
KOPIA_SERVER_PASSWORD=<contraseña generada>
KOPIA_SERVER_CONTROL_USERNAME=control-respaldos
KOPIA_SERVER_CONTROL_PASSWORD=<contraseña generada>

KOPIA_STORAGE_TYPE=s3
KOPIA_S3_BUCKET=mi-bucket-de-respaldos
KOPIA_S3_ACCESS_KEY=<access key>
KOPIA_S3_SECRET_ACCESS_KEY=<secret key>

KOPIA_IDENTITY_USER=hefesto
KOPIA_IDENTITY_HOST=srv-respaldos
```

Sobre las claves del bucket: usá una **clave de aplicación dedicada**, no la
clave raíz de la cuenta. Ver `03-VARIABLES-Y-COMO-OBTENERLAS.md`.

### Antes de seguir: guardá la clave del repositorio

Copiá `KOPIA_PASSWORD` **ahora** a un gestor de contraseñas. No esperes a la
primera emergencia. Es la única clave que descifra los respaldos y no hay
manera de recuperarla si se pierde.

## 5. Crear el repositorio

**Este paso va antes de levantar el servidor.** Upstream lo pide explícitamente
en la guía del Repository Server: primero se crea y configura el
repositorio, después se levanta el servidor.

```bash
./scripts/crear-repositorio.sh
```

Qué hace:

1. Verifica que no haya ya un repositorio (no pisa nada).
2. Corre `kopia repository create <tipo>` con los flags de tu backend.
3. Fija la política global de retención y compresión.
4. Designa esa instancia como **propietaria del mantenimiento**.
5. Deja un resumen en `manifiestos/repositorio-*.resumen.txt` sin secretos.

Salida esperada, resumida:

```
[ OK ] Repositorio creado.
[ OK ] Politica global aplicada.
[ OK ] Esta instancia quedo como propietaria del mantenimiento.
```

> **Por qué el paso del mantenimiento importa:** si esa máquina se apaga o se
> cambia, **nadie más corre mantenimiento**. El repositorio deja de purgar y
> crece sin control. Ver `05-RESPALDOS-Y-RESTAURACION.md`.

## 6. Levantar el servidor

```bash
docker compose up -d
docker compose ps
```

`ps` tiene que mostrar el servicio en `healthy`. El healthcheck espera hasta
90 segundos la primera vez, porque tiene que abrir el repositorio.

```bash
# Si tarda o falla, mirá los logs
docker compose logs -f kopia
```

El puerto está ligado a `127.0.0.1` por defecto. Desde tu máquina:

```bash
ssh -L 51515:127.0.0.1:51515 usuario@servidor
```

Y abrí <http://127.0.0.1:51515>.

> La URL usa **http** porque no hay TLS configurado. Solo es aceptable por
> túnel SSH. Para exponerla de verdad, seguí `02-INSTALACION-COOLIFY.md`.

## 7. Crear el primer usuario de cliente

La cuenta `KOPIA_SERVER_USERNAME` es para **administrar el servidor**. Los
clientes que respaldan usan cuentas propias.

```bash
docker compose exec kopia /bin/kopia server user add cliente@srv-datos
```

El usuario se identifica como `usuario@servidor`, **en minúsculas**, y el
servidor es el hostname de la máquina cliente. Para descubrirlo:

```bash
# En la maquina cliente
hostname
```

Detalle de permisos reales: `04-PRIMERA-CUENTA-Y-USUARIOS.md`.

## 8. Conectar el primer cliente

En la máquina **del cliente** (no en el servidor):

```bash
export KOPIA_PASSWORD='<clave del repositorio>'

docker run --rm -it \
  -e KOPIA_PASSWORD \
  -v kopia-cliente-config:/app/config \
  -v kopia-cliente-cache:/app/cache \
  kopia/kopia:0.23.1@sha256:89fd95ee2942880ca00eae964266958a394421ddbdf69bca62e38afc55f5900e \
  repository connect server \
    --url=http://DIRECCION_DEL_SERVidor:51515 \
    --server-username=cliente@srv-datos \
    --server-password=<contraseña del usuario> \
    --override-hostname=srv-datos \
    --override-username=cliente
```

Sobre `--override-hostname` / `--override-username`: **no son opcionales en la
práctica.** Sin ellos, si el hostname de la máquina cambia, la nueva máquina
aparece como un origen sin historia y las instantáneas viejas dejan de
purgarse. Ver `05-RESPALDOS-Y-RESTAURACION.md`.

Sin TLS no podés conectar clientes remotos de verdad: el protocolo GRPC que
usa el Repository Server necesita TLS. Upstream es explícito:

> *"you start your kopia server with a certificate (`--insecure` does not work,
> as GRPC needs TLS, which is used by Repository Server)"*
> — <https://kopia.io/docs/repository-server/#kopia-behind-a-reverse-proxy>

Pasá directo a `02-INSTALACION-COOLIFY.md` para la variante con proxy y TLS.

## 9. Primer respaldo

```bash
# En el cliente
./scripts/respaldar.sh --fuente /srv/datos --etiqueta primer-respaldo
```

Salida esperada:

```
[ OK ] /srv/datos
[ OK ] Instantanea de /srv/datos creada.
[ OK ] Manifiesto: .../manifiestos/respaldo-primer-respaldo-....manifiesto.json
[ OK ] SHA-256:    3f9a...
[ OK ] Marcado como COMPLETO: .../registros/....completo
```

## 10. Verificar

**Este es el paso que separa a un respaldo de una hipótesis.**

```bash
./scripts/verificar.sh --porcentaje 100
```

Códigos de salida:

| Código | Significado |
|---|---|
| `0` | OK |
| `1` | La verificación encontró errores |
| `2` | Argumentos incorrectos |
| `3` | Falta configuración o repositorio |

Para monitoreo, lo mínimo razonable es **1 % diario**:

```bash
# Crontab del cliente
15 4 * * *  cd /opt/hefesto-respaldo-kopia && ./scripts/verificar.sh --porcentaje 1 >> registro-cron.log 2>&1
```

Upstream explica por qué 1 % diario sirve: estadísticamente, a lo largo de un
año, se termina cubriendo ~98 % de los datos.

## 11. Automatizar el respaldo diario

```bash
# /etc/cron.d/respaldo-kopia
# Importante: conviene que el respaldo NO se solape con la ventana de mantenimiento.
30 2 * * * hefesto cd /opt/hefesto-respaldo-kopia && ./scripts/respaldar.sh --fuente /srv/datos --etiqueta diario >> registros/cron-respaldo.log 2>&1
```

Rutas a respaldar, en el `.env`:

```dotenv
RUTAS_RESPALDO="/srv/datos /srv/documentos"
```

## 12. Qué revisar antes de dar por buena la instalación

- [ ] `docker compose ps` dice `healthy`.
- [ ] La clave del repositorio está en un gestor de contraseñas.
- [ ] `kopia maintenance info` muestra el propietario esperado.
- [ ] Hay al menos una instantánea.
- [ ] `verificar.sh --porcentaje 100` devolvió `0`.
- [ ] El puerto 51515 **no** está expuesto a internet.
- [ ] El bucket no tiene versión `latest` sin digest.

Checklist completo en `07-PRUEBAS-DE-ACEPTACION.md`.

---

## Si algo falla

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| El contenedor reinicia en bucle | El repositorio no existe | Corré `crear-repositorio.sh` primero |
| `no such host` / credenciales | Bucket, endpoint o claves incorrectos | Revisá `.env` y el endpoint S3 |
| `repository status` dice que no es un repositorio directo | El cliente está conectado por servidor | Es normal; `repo status` es de bajo nivel |
| El healthcheck queda `unhealthy` | Credenciales de la API incorrectas | Revisá `KOPIA_SERVER_USERNAME` / `KOPIA_SERVER_PASSWORD` |
| El repositorio crece sin parar | Nadie está corriendo mantenimiento | Mirá `05-RESPALDOS-Y-RESTAURACION.md` |

## Fuentes

- Repositorio y almacenamiento: <https://kopia.io/docs/repositories/>
- Repository Server: <https://kopia.io/docs/repository-server/>
- Verificación: <https://kopia.io/docs/advanced/consistency/>
- Mantenimiento: <https://kopia.io/docs/advanced/maintenance/>
- Inicio: <https://kopia.io/docs/getting-started/>