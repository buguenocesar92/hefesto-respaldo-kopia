# 03 — Variables de entorno: qué son, de dónde salen, qué pasa si cambian

Toda variable del `.env` está acá, con su origen y su consecuencia real.

> **Ninguna variable de este kit tiene un valor por defecto de upstream que
> sirva para producción.** Las que no son obligatorias son decisiones de
> Hefesto, y están marcadas como tales.

---

## Generar los secretos

```bash
# Clave del repositorio: 48 bytes, sin '=' ni saltos de línea
openssl rand -base64 48 | tr -d '\n=' ; echo

# Contraseñas de interfaz y control: 32 bytes
openssl rand -base64 32 | tr -d '\n=' ; echo
openssl rand -base64 32 | tr -d '\n=' ; echo
```

Si `openssl` no está instalado:

```bash
sudo apt-get install -y openssl
```

Nunca generes estos valores a mano, nunca los pegues en un ticket, nunca los
compartas por chat.

---

## Tabla de variables

### Identificación

| Variable | Obligatoria | Ejemplo | De dónde sale | Si la cambiás a posteriori |
|---|---|---|---|---|
| `KOPIA_TIMEZONE` | No | `America/Santiago` | Tu zona | Solo afecta la presentación de las marcas de tiempo |
| `KOPIA_SERVER_NOMBRE` | No | `respaldos-hefesto` | Nombre del proyecto | Solo cambia la etiqueta del contenedor |

### Exposición

| Variable | Obligatoria | Ejemplo | De dónde sale | Si la cambiás a posteriori |
|---|---|---|---|---|
| `PUERTO_KOPIA` | No | `51515` | Puerto de upstream | Hay que reiniciar el contenedor. Cambiarlo rompe las conexiones de los clientes |
| `KOPIA_BIND_HOST` | No | `127.0.0.1` | Decisión de seguridad | **No lo cambies a `0.0.0.0` sin TLS y proxy.** Con `0.0.0.0` el puerto queda escuchando en todas las interfaces del servidor |

### Secretos

| Variable | Obligatoria | De dónde sale | Si la cambiás a posteriori |
|---|---|---|---|
| `KOPIA_PASSWORD` | **# OBLIGATORIA** | `openssl rand -base64 48` | **Ver la sección de abajo. No es trivial.** |
| `KOPIA_SERVER_PASSWORD` | **# OBLIGATORIA** | `openssl rand -base64 32` | Reiniciá el contenedor. Los usuarios con sesión abierta se caerán |
| `KOPIA_SERVER_USERNAME` | **# OBLIGATORIA** | Lo elegís | Reiniciá el contenedor. También hay que actualizar los clientes que usan esta cuenta |
| `KOPIA_SERVER_CONTROL_PASSWORD` | **# OBLIGATORIA** | `openssl rand -base64 32` | Reiniciá el contenedor |
| `KOPIA_SERVER_CONTROL_USERNAME` | No | `control-respaldos` | Reiniciá el contenedor |

> **Trampa importante con `KOPIA_SERVER_USERNAME`.** El mismo nombre de
> variable lo usan dos cosas distintas:
> - En `kopia server start` → el usuario de la interfaz web (básico).
> - En `kopia server status`, `kopia server refresh` → el **control**.
>
> Es deliberado: el healthcheck del contenedor reutiliza las mismas variables
> para autenticarse sin escribir un secreto en el comando. Verificado en
> `cli/command_server.go` (bloques `serverFlags` y `serverClientFlags`).

### Almacenamiento

| Variable | Obligatoria | De dónde sale | Si la cambiás a posteriori |
|---|---|---|---|
| `KOPIA_STORAGE_TYPE` | **# OBLIGATORIA** | `s3`, `azure`, `b2`, `gcs`, `webdav`, `sftp`, `filesystem` | **No se cambia.** El tipo de almacenamiento queda grabado en el repositorio. Cambiarlo implica crear otro repositorio |
| `KOPIA_S3_BUCKET` | Sí si es `s3` | Lo creás vos en el proveedor | Requiere migrar el repositorio |
| `KOPIA_S3_ENDPOINT` | No | Lo da el proveedor | Solo afecta conexiones **nuevas** |
| `KOPIA_S3_REGION` | No | Lo da el proveedor | Ídem |
| `KOPIA_S3_ACCESS_KEY` | Sí si es `s3` | Panel del proveedor | **Sí se puede rotar**: desconectá y reconectá el repo con la clave nueva |
| `KOPIA_S3_SECRET_ACCESS_KEY` | Sí si es `s3` | Ídem | Ídem |
| `KOPIA_FILESYSTEM_PATH` | Sí si es `filesystem` | Ruta del NAS o disco | Solo para pruebas. No protege de perder el servidor |

> **Kopia no crea almacenamiento.** Tenés que tener la cuenta, el bucket y las
> credenciales **antes** de crear el repositorio. Upstream lo repite en todas
> las guías: *"You must provision, setup, and pay (the storage provider) for
> whatever storage locations you want to use before you create a repository."*

### Política y scripting

| Variable | Obligatoria | Por defecto | Qué hace |
|---|---|---|---|
| `POLITICA_KEEP_LATEST` | No | `7` | Instantáneas más recientes que se conservan |
| `POLITICA_KEEP_HOURLY` | No | `24` | Máximo de instantáneas por hora |
| `POLITICA_KEEP_DAILY` | No | `14` | Máximo por día |
| `POLITICA_KEEP_WEEKLY` | No | `8` | Máximo por semana |
| `POLITICA_KEEP_MONTHLY` | No | `6` | Máximo por mes |
| `POLITICA_KEEP_ANNUAL` | No | `2` | Máximo por año |
| `POLITICA_COMPRESSION` | No | `zstd` | **Upstream lo tiene desactivado por defecto.** Decisión de Hefesto usar `zstd` |
| `KOPIA_IDENTITY_USER` | No | `hefesto` | Ver la sección de identidad, abajo |
| `KOPIA_IDENTITY_HOST` | No | `srv-respaldos` | Ídem |

> Los periodos de retención **se superponen a propósito**. `keep-daily 14`
> no significa "los últimos 14 días": significa "de cada día, conservá hasta 14
> instantáneas, salvo que una regla más fina ya haya guardado esa". Un cliente
> que espere "14 días de historial" tiene que probarlo con `kopia snapshot list`.

### Verificación

| Variable | Por defecto | Qué hace |
|---|---|---|
| `VERIFICAR_PORCENTAJE` | `1` | Porcentaje de archivos que se descargan y descifran al verificar |
| `VERIFICAR_PARALELISMO` | `4` | Hilos de verificación |
| `VERIFICAR_MAX_ERRORES` | `1` | Cuántos errores tolera antes de cortar |

---

## `KOPIA_PASSWORD` — la que no se puede recuperar

> **La contraseña del repositorio es la única clave que descifra los
> respaldos.** Si se pierde, los respaldos son inservibles aunque los datos
> estén intactos en el bucket.

Upstream:

> *"There is no way to recover it or the files and folders within that
> repository. Store your repository password in a safe place."*
> — <https://kopia.io/docs/faqs/#how-do-i-enable-encryption>

### ¿Se puede cambiar después?

Sí, **pero solo si estás conectado al repositorio**:

```bash
kopia repository change-password
```

> *"This means that you **cannot** reset your password if you forget your
> password and you are NOT still connected to your repository, because you will
> need your current password to connect."*

Consecuencia práctica: si tenés varios clientes conectados, cambiá la clave
desde **uno** de ellos y actualizá el `KOPIA_PASSWORD` en **todos** antes de
que alguno lose la conexión. Un cliente con la contraseña vieja simplemente no
puede volver a conectarse.

### Cambio de clave: procedimiento

1. Confirmá que la clave nueva está en el gestor de contraseñas.
2. Elegí un cliente que esté **conectado** en ese momento.
3. `kopia repository change-password`
4. Actualizá `KOPIA_PASSWORD` en el `.env` del servidor.
5. Actualizá `KOPIA_PASSWORD` en cada cliente.
6. Reiniciá el servidor de repositorios.
7. `docker compose restart kopia`

### Reglas de custodia

- **Nunca** reutilizar la clave del repositorio como contraseña del bucket, de
  la interfaz, ni de nada más. Upstream lo dice de los backends con
  contraseña: *"This password can be whatever you want, it does not need to be
  the same as your [storage] password. In fact, it should not be the same!"*
- La clave del repositorio **no** se envía nunca a ningún servidor: el
  cifrado es extremo a extremo, el cliente cifra y el almacenamiento solo ve
  texto cifrado.
- Prueba de custodia trimestral: alguien ajeno al servidor tiene que poder
  recuperar la clave y llegar a `kopia snapshot list`.

---

## `KOPIA_IDENTITY_HOST` / `KOPIA_IDENTITY_USER` — el riesgo silencioso

Kopia identifica un origen como **`usuario@servidor:ruta`**. Si reconstruís una
máquina y el hostname cambia, la máquina nueva **aparece como un origen sin
historial**:

- Las instantáneas viejas quedan pegadas al origen viejo, que ya no existe.
- La política de retención deja de purgar esas instantáneas.
- El repositorio crece sin que nadie lo note.

**La solución es fijar la identidad.** En el servidor:

```dotenv
KOPIA_IDENTITY_USER=hefesto
KOPIA_IDENTITY_HOST=srv-respaldos
```

`crear-repositorio.sh` los aplica con:

```bash
--override-hostname=srv-respaldos
--override-username=hefesto
```

Y en cada cliente, al conectar, hay que pasar lo mismo:

```bash
kopia repository connect server --url=... \
  --override-hostname=srv-datos \
  --override-username=cliente
```

> **Este es el tipo de detalle que salva a un cliente.** Si el servicio se
> llama "Respaldo gestionado" y a los seis meses el repositorio vale el triple
> porque nadie purgó nada, el problema fue una variable de entorno.

Para ver los orígenes actuales:

```bash
kopia snapshot list --all
```

---

## `KOPIA_TLS_FINGERPRINT`

| Campo | Detalle |
|---|---|
| Obligatoria | Solo si usás `compose.tls.yaml` |
| Ejemplo | `48537cce585fed39fb26c639eb8ef38143592ba4b4e7677a84a31916398d40f7` |
| De dónde sale | La imprime Kopia al arrancar con `--tls-generate-cert`, o `openssl x509 -in kopia.crt -noout -fingerprint -sha256 \| sed 's/://g' \| cut -f 2 -d =` |
| ¿Es un secreto? | **No.** Es pública. Upstream la imprime justamente para que se anote |

Si cambia el certificado, hay que actualizar esta variable **y** la que usan
los clientes, o la conexión falla.

---

## Variables de otros backends

Solo aparecen en `.env` si el tipo de almacenamiento las necesita. Los nombres
y flags están verificados contra
<https://kopia.io/docs/repositories/>.

| Backend | Variables | Comando de creación |
|---|---|---|
| `azure` | `KOPIA_AZURE_CONTAINER`, `KOPIA_AZURE_STORAGE_ACCOUNT`, `KOPIA_AZURE_STORAGE_KEY` o `KOPIA_AZURE_SAS_TOKEN` | `kopia repository create azure --container= --storage-account= --storage-key=` |
| `b2` | `KOPIA_B2_BUCKET`, `KOPIA_B2_KEY_ID`, `KOPIA_B2_KEY` | `kopia repository create b2 --bucket= --key-id= --key=` |
| `gcs` | `KOPIA_GCS_BUCKET`, `KOPIA_GCS_CREDENTIALS_FILE` | `kopia repository create gcs --bucket= --credentials-file=` |
| `webdav` | `KOPIA_WEBDAV_URL`, `KOPIA_WEBDAV_USERNAME`, `KOPIA_WEBDAV_PASSWORD` | `kopia repository create webdav --url= --webdav-username= --webdav-password=` |
| `sftp` | `KOPIA_SFTP_PATH`, `KOPIA_SFTP_HOST`, `KOPIA_SFTP_USERNAME`, `KOPIA_SFTP_PASSWORD` o `KOPIA_SFTP_KEYFILE` | `kopia repository create sftp --path= --host= --username= --sftp-password=` |
| `filesystem` | `KOPIA_FILESYSTEM_PATH` | `kopia repository create filesystem --path=` |

**Backends que este kit NO cubre:** `rclone` y `gdrive`. Upstream los marca
como experimentales:

> *"Rclone support is experimental"*
> *"Native support for Google Drive in Kopia is currently experimental"*
> — <https://kopia.io/docs/repositories/>

Se los deja fuera a propósito: no corresponde vender en producción algo que
upstream declara experimental sin pruebas propias.

---

## TLS del backend de almacenamiento

**Este kit nunca recomienda desactivar la verificación TLS del backend.**

Si algún proveedor te pide "ignorar certificado", eso es un compromiso grave:
el tráfico de autenticación contra el bucket viaja sin verificar y se puede
interceptar. Kopia expone opciones para esto, pero acá no se usan y no
deberían usarse.

Si el certificado es autoemitido y es **tu** bucket, la respuesta correcta es
instalar la CA en el sistema, no desactivar la comprobación.

## Fuentes

- FAQ (cifrado, compresión, contraseña): <https://kopia.io/docs/faqs/>
- Almacenamientos: <https://kopia.io/docs/repositories/>
- Inicio rápido: <https://kopia.io/docs/getting-started/>
- Repository Server: <https://kopia.io/docs/repository-server/>
- Banderas y variables (`cli/command_server.go`,
  `cli/command_repository_connect.go`): <https://github.com/kopia/kopia/tree/master/cli>
- Dockerfile: <https://github.com/kopia/kopia/blob/master/tools/docker/Dockerfile>