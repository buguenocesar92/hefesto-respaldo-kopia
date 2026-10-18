# 05 — Respaldos y restauración

El documento operativo del kit. Acá está todo lo que hay que saber para que
los respaldos sirvan de algo.

---

## 1. Lo que Kopia respalda, y lo que no

**Kopia respalda archivos y directorios.** Eso es todo.

| ¿Respaldado? | Detalle |
|---|---|
| Archivos y carpetas | Sí, es lo único que hace |
| Metadatos | Sí: permisos, dueño, grupo, fechas, enlaces simbólicos |
| El sistema operativo | **No.** Sin kernel, sin paquetes, sin usuarios, ni cron |
| El estado de una base de datos en ejecución | **No de forma consistente.** Respaldá el volcado, no el volumen |
| El contenido del bucket | No. El bucket **es** el repositorio |
| Un servidor entero como imagen de disco | **No existe.** No lo vendas así |

> **Límite comercial importante:** si el cliente quiere "restaurar el servidor
> completo", hay que decirlo de entrada. Esto no lo hace. Necesita otra guía
> aparte, y probablemente otra herramienta.

---

## 2. Qué es persistente en este kit, y qué hay que respaldar

| Ruta / volumen | Qué guarda | ¿Hay que respaldarlo? |
|---|---|---|
| Volumen `kopia-config` (`/app/config`) | `repository.config`: **dónde está el almacenamiento y con qué clave** | **SÍ. Es lo más crítico.** Sin este archivo, hay que reconectar a mano |
| Volumen `kopia-cache` (`/app/cache`) | Caché local | No. Se regenera. Borrarlo cuesta tiempo, no datos |
| Volumen `kopia-logs` (`/app/logs`) | Logs | No, salvo que quieras auditoría |
| El bucket / NAS | **Los datos** | Es el respaldo. Es lo que hay que proteger fuera de este servidor |
| El `.env` | Contraseñas | **SÍ, pero fuera del servidor y cifrado** |

### Lo que NO se respalda

- **La clave del repositorio.** Si la perdés, los respaldos son inservibles.
- **El script de despliegue.** Guardá el `.env` y la configuración de
  infraestructura en un repositorio seguro.
- **La configuración del bucket.** Las políticas de retención del proveedor, el
  versioning, los logs de acceso.

### Los secretos que hay que conservar aparte

| Secreto | Dónde | Si se pierde |
|---|---|---|
| `KOPIA_PASSWORD` | Gestor de contraseñas | **Respaldos irrecuperables** |
| Claves del bucket | Gestor de contraseñas | Hay que reconfigurar el acceso al repositorio |
| `KOPIA_SERVER_PASSWORD` | Gestor de contraseñas | Se cambia; no hay pérdida de datos |
| Certificado TLS (si es propio) | Gestión de certificados | Se regenera |

---

## 3. Cómo obtener una copia coherente

Kopia garantiza que el **índice** del snapshot siempre está consistente. Lo que
no garantiza es que el **contenido** de un archivo que se estaba escribiendo
esté completo.

Si tu aplicación escribe mientras Kopia lee, podés obtener un snapshot
correctamente formado que contiene un archivo truncado. Kopia no lo detecta.

### Qué hacer según el caso

| Caso | Solución |
|---|---|
| Archivos estáticos (documentos, código) | Respaldar directo |
| Base de datos | **Volcado propio** (`pg_dump`, `mysqldump`, `mongodump`) y respaldar el volcado |
| Volumen Docker de una app | Detener el contenedor mientras se respalda |
| Archivos de configuración | Directo |

### Cómo lo resuelve este kit

`respaldar.sh` expone `--pausar` y `--reanudar`:

```bash
./scripts/respaldar.sh \
  --fuente /var/lib/postgresql/data \
  --pausar "docker stop postgres" \
  --reanudar "docker start postgres"
```

Los comandos se ejecutan **alrededor** del respaldo, con una trampa (`trap`)
que garantiza que los escritores vuelvan a levantarse **aunque el respaldo
falle a mitad**. Ver `scripts/respaldar.sh`.

> Un ejemplo completo, marcado como demostración, está en
> `ejemplos/02-respaldo-docker-volume.DEMOSTRACION.sh`.

---

## 4. Manifiesto y sumas de comprobación

Cada corrida de `respaldar.sh` deja cuatro cosas:

| Archivo | Contenido |
|---|---|
| `registros/respaldo-<etiqueta>-<fecha>.log` | Registro completo de la ejecución |
| `registros/….en-proceso` | Marcador **mientras corre** |
| `manifiestos/….manifiesto.json` | Datos de la instantánea en JSON |
| `manifiestos/….manifiesto.json.sha256` | SHA-256 del manifiesto |
| `registros/….completo` | **Solo si todo salió bien** |

Contenido del manifiesto:

```json
{
  "kit": "hefesto-respaldo-kopia",
  "version_kit": "1.0.0",
  "corrida": "respaldo-diario",
  "etiqueta": "diario",
  "inicio_utc": "20261016T031500Z",
  "fin_utc": "20261016T031842Z",
  "identidad_host": "srv-respaldos",
  "identidad_user": "hefesto",
  "modo_ejecucion": "contenedor",
  "origenes": ["/srv/datos"],
  "instantanea_manifesto_id": "9a622e33ab134ef440f76ed755f79c2f",
  "instantanea_raiz_id": "kfe997567fb1cf8a13341e4ca11652f70",
  "origenes_con_error": 0,
  "estado": "completado"
}
```

### La marca de completado

> **El respaldo se marca como completo solo al terminar bien. Nunca antes.**

Si el proceso muere a mitad, queda el `.en-proceso` y **no** hay `.completo`.
Un respaldo sin `.completo` no cuenta como respaldo. Es la diferencia entre
"corrió el cron" y "hay una copia recuperable".

### Para qué sirve el SHA-256

- **Del manifiesto:** detecta si el registro fue alterado.
- **De los archivos restaurados:** `restaurar.sh` deja un muestreo de hasta 100
  archivos con su SHA-256, para comparar contra una segunda restauración.

> **Lo que el SHA-256 NO es:** no es una copia del contenido. Los datos siguen
> cifrados en el repositorio. El hash sirve para auditar y comparar, no para
> recuperar.

---

## 5. Verificación: el respaldo que nadie prueba es una hipótesis

### Qué verifica Kopia

Upstream lo divide en dos niveles
(<https://kopia.io/docs/advanced/consistency/>):

| Nivel | Qué hace | Qué NO detecta |
|---|---|---|
| `kopia snapshot verify` (por defecto) | Recorre las instantáneas, comprueba la consistencia de los índices y que cada entrada tenga su blob | **No descarga ni descifra nada.** No detecta corrupción posterior |
| `--verify-files-percent=N` | Además descarga, descifra y descomprime un N% aleatorio | Con N<100, no revisa todos los archivos |

Con `--verify-files-percent=100` el resultado es, en la práctica, **una
restauración de prueba sin escribir nada en disco**: los archivos se
descargan a un temporal y se descartan.

Upstream, textual:

> *"If Kopia throws no errors while running this command, then your
> snapshots/repositories are valid."*

Y también:

> *"The gold standard for testing the validity of backups is to simply restore
> the snapshot; if restore is successful, then the backup is valid."*

### Cadencia recomendada

| Frecuencia | Porcentaje | Costo |
|---|---|---|
| Diaria | `1` | Bajo. A lo largo del año cubre ~98% de los datos |
| Mensual | `100` | Alto: ancho de banda y tiempo. Es la prueba real |

```bash
# Diario, para monitoreo
./scripts/verificar.sh --porcentaje 1

# Mensual, la prueba de verdad
./scripts/verificar.sh --porcentaje 100
```

> Kopia corre `kopia snapshot verify` **automáticamente** en cada mantenimiento
> completo diario. Eso cubre la verificación estructural, **no** la descarga de
> archivos. No alcanza por sí solo.

### Código de salida

`verificar.sh` devuelve:

| Código | Significado |
|---|---|
| `0` | OK |
| `1` | Se encontraron errores de integridad |
| `2` | Argumentos incorrectos |
| `3` | Falta configuración o repositorio |

Es usable directamente en un monitor.

---

## 6. Restauración

### 6.1 Ver las instantáneas

```bash
./scripts/restaurar.sh --listar
kopia snapshot list --all          # incluye orígenes ajenos al propio
kopia snapshot list /ruta/origen   # el historial de una ruta
```

### 6.2 Explorar antes de copiar

Upstream recomienda **montar** como la vía normal de restaurar:

```bash
kopia mount ID_INSTANTANEA /mnt/montaje &
ls -la /mnt/montaje/
# copiar lo que necesites
umount /mnt/montaje
```

`kopia mount` usa FUSE. **Dentro de Docker eso necesita privileges que el
compose de este kit no pide a propósito.** Si lo necesitás en una recuperación
puntual:

```bash
docker run --rm -it \
  --device /dev/fuse --cap-add SYS_ADMIN \
  --security-opt apparmor:unconfined \
  -e KOPIA_PASSWORD \
  -v kopia-config:/app/config -v kopia-cache:/app/cache \
  -v /mnt:/mnt \
  kopia/kopia:0.23.1@sha256:... mount ID_INSTANTANEA /mnt/montaje
```

En macOS: `kopia mount --webdav` es la opción recomendada y no requiere
software extra. En Windows: `kopia mount all Z:` usa WebDAV y necesita el
servicio `WebClient` habilitado.

### 6.3 Restaurar con `restaurar.sh`

```bash
./scripts/restaurar.sh ID_INSTANTANEA /mnt/recuperacion \
  --servidor "docker compose -f /opt/app/compose.yaml stop app"
```

Qué hace, en orden:

1. **Valida el destino.** Ruta absoluta, sin `..`, no un directorio del
   sistema, no un enlace simbólico.
2. **Rechaza destinos con datos**, salvo `--force` explícito.
3. Detiene el servicio **solo si le indicás cuál**, con `--servidor`.
4. Corre `kopia snapshot restore` y **propaga el código de salida real**.
5. Deja un muestreo de SHA-256.
6. **Deja el servicio detenido** y lo dice.

> Nunca borra nada. Nunca sobrescribe automáticamente. Ante un destino
> ocupado, se niega y te explica por qué.

### 6.4 La prueba final: restauración desde cero

El procedimiento completo, para el escenario en que se perdió el servidor,
está en **`scripts/restaurar-desde-cero.md`**. Leelo antes de necesitarlo.

---

## 7. Identidad del origen: el riesgo silencioso

Kopia identifica un origen como **`usuario@servidor:ruta`**.

Si se reconstruye una máquina y cambia el hostname, la máquina nueva aparece
como **un origen sin historial**. Consecuencias:

- Las instantáneas viejas siguen existiendo, pero quedan bajo un origen vacío.
- La política de retención ya no las considera: **dejan de purgarse**.
- El repositorio crece sin que nadie lo note.
- El cliente cree que tiene historial y no lo tiene.

### La solución

Fijar la identidad en el momento de crear y de conectar:

```bash
--override-hostname=srv-respaldos
--override-username=hefesto
```

En este kit:

| Dónde | Cómo |
|---|---|
| Servidor | `KOPIA_IDENTITY_HOST` / `KOPIA_IDENTITY_USER` en el `.env`, aplicados por `crear-repositorio.sh` |
| Cliente | `--override-hostname` / `--override-username` al conectar |

Si el hostname **ya** cambió y las instantáneas viejas quedaron atrás, se
pueden Adoptar renombrando el origen… que en la práctica significa conectar de
nuevo con los `--override` correctos. Verificá siempre con:

```bash
kopia snapshot list --all
```

---

## 8. Mantenimiento: la otra mitad del respaldo

Kopia no borra datos automáticamente al vencer una retención. Lo hace el
**mantenimiento**.

| Tipo | Qué hace | Frecuencia por defecto |
|---|---|---|
| **Quick** | Mantiene bajos los blobs frecuentes, para rendimiento. Nunca borra metadatos sin copia | ~cada hora |
| **Full** | Purga lo que ya no es alcanzable y compacta. Incluye el Snapshot GC | cada 24 horas |

### El propietario del mantenimiento

Upstream:

> *"For correctness reasons, Kopia requires that no more than one instance of
> certain maintenance operations runs at any given time. To achieve that, one
> repository `user@hostname` is designated as the Maintenance Owner. Other
> repository users will not attempt to run maintenance automatically."*

> **Si el propietario está apagado, NO hay mantenimiento.** El repositorio deja
> de purgar basura de deduplicación y **crece sin control**. Es el modo de
> falla más caro de este producto.

Verificar:

```bash
kopia maintenance info
```

```
Owner: root@myhost
```

Cambiar:

```bash
kopia maintenance set --owner=me
kopia maintenance set --owner=otro@servidor
```

Ajustar intervalos:

```bash
kopia maintenance set --enable-quick true
kopia maintenance set --enable-full true
kopia maintenance set --quick-interval=2h
kopia maintenance set --full-interval=8h
```

Correr a mano (solo el propietario puede):

```bash
kopia maintenance run            # quick
kopia maintenance run --full     # full
```

> **Los efectos del mantenimiento completo no son inmediatos.** Upstream:
> *"the effects of full maintenance are not immediate - it may take several hours
> and/or multiple maintenance cycles to remove blobs that are not in use."*

> **Nunca uses `--safety=none`** salvo que puedas garantizar que no hay ningún
> snapshot en curso. Upstream: *"Failure to do so can introduce repository
> corruption."*

### Regla operativa

El servidor de respaldos **no se apaga nunca**. Si es un VPS, que tenga
reinicio automático y monitoreo. Si se va a mantener apagado, hay que
designar otro propietario que sí esté encendido.

---

## 9. Protección contra ransomware

Un ransomware busca las llaves del almacenamiento y borra los respaldos. Kopia
ofrece protección real, pero hay que configurarla **en el bucket**.

### 9.1 Claves de aplicación restringidas

La medida más simple y más efectiva: una clave **sin permiso de borrado**.

Upstream explica por qué esto no rompe el mantenimiento:

> *"When Kopia deletes data from a compatible provider, it is replacing the data
> with a special file that has a `hidden` marker. This makes the file appear to
> be deleted, but it can still be accessed by using an older versión of the
> file. Typically, the cloud provider offers 'Lifecycle-Management' to apply a
> true-deletion of hidden data after a certain period of time."*

Es decir: Kopia **nunca borra de verdad**. Le pone una marca. El borrado real lo
hace el proveedor, después de un período.

Para AWS, la política sugerida por upstream:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Stmt1480692207000",
            "Effect": "Deny",
            "Action": [
                "s3:DeleteBucket",
                "s3:DeleteBucketPolicy",
                "s3:DeleteBucketWebsite",
                "s3:DeleteObjectVersion"
            ],
            "Resource": ["arn:aws:s3:::*"]
        }
    ]
}
```

Después: desconectar y reconectar el repositorio con la clave nueva.

### 9.2 Object Lock (inmutabilidad)

Dónde funciona, según upstream:

| Backend | ¿Object Lock? |
|---|---|
| **S3** (y compatibles) | **Sí**, con `--retention-mode` |
| **Azure Blob** | **Sí**, con inmutabilidad a nivel de versión |
| **Google Cloud Storage** | **Sí**, con retención de objetos |
| **Backblaze B2 (motor `b2`)** | **No.** Hay que usar el motor `s3` con `--endpoint` |
| WebDAV, SFTP, filesystem | **No** |

Configuración (S3):

```bash
kopia repository create s3 \
  --bucket=mi-bucket \
  --access-key=... --secret-access-key=... \
  --retention-mode COMPLIANCE \
  --retention-period 30d

# Renovar las fechas de retención automáticamente:
kopia maintenance set --extend-object-locks true
```

> **Condición de upstream:** el `full-interval` debe ser **al menos un día más
> corto** que el `retention-period`, o Kopia no habilita la extensión de
> Object Lock. Si no se renueva, la fecha de retención vence y los datos dejan
> de estar protegidos.

### 9.3 Lifecycle Management

Con Object Lock, los objetos marcados como borrados siguen ocupando espacio.
Hay que habilitar **Lifecycle Management** en el bucket, idealmente con el
mismo período que la retención.

### 9.4 MFA y rotación

- Activá MFA en la cuenta del proveedor.
- **Eliminá las claves raíz o globales.** Upstream: *"they can generally be
  used to execute nearly any task you can do when you're logged in (effectively
  bypassing MFA)."*

### 9.5 El límite, dicho con todas las letras

Upstream advierte dos cosas:

1. **El ransomware puede ser lento.** Puede pasar semanas cifrando lo que no se
   usa y golpear al final lo que sí. Puede que **no exista una instantánea
   única** que represente un estado bueno de todos tus archivos. La
   recuperación puede ser larga.
2. **El Object Lock se puede usar en contra.** Como los bloqueos no se pueden
   reducir ni quitar, un ransomware podría subir mucho con un bloqueo larguísimo
   e imposible de borrar. **Poné cuotas y límites de costo en el bucket.**

---

## 10. Límites conocidos y qué hacer ante un fallo

| Límite | Qué hacer |
|---|---|
| Un snapshot largo queda marcado `incomplete` hasta que termina | Es normal. Kopia crea checkpoints para que no se purguen a mitad. Esperar |
| No se puede guardar un snapshot en dos repositorios a la vez | Conectarse a varios repositorios y replicar políticas |
| Un origen con hostname cambiado queda sin historial | `--override-hostname` desde el principio |
| Mantenimiento sin propietario = crecimiento indefinido | Monitorear `kopia maintenance info` |
| Restauración parcial si falla a mitad | **No usar** ese destino. Repetir en uno nuevo |
| Reloj desincronizado puede causar inconsistencias | NTP en todos los clientes. Upstream lo lista entre las tres causas de corrupción |
| Sistema de archivos sin semántica POSIX completa | Upstream recomienda los más maduros, o almacenamiento en la nube |

### Causas de corrupción según upstream

1. **Sistema de archivos mal configurado o no compatible.** Kopia necesita
   semántica POSIX, escrituras atómicas y consistencia de lectura. Muchos
   sistemas de archivos en red no la garantizan.
2. **Corrupción silenciosa tras la escritura** (bit rot). RAID **no** protege
   contra esto; solo contra indisponibilidad.
3. **Desfase de reloj grande.** Upstream recomienda NTP en todos los nodos.

### Ante corrupción

1. **No borres ni muevas archivos a ciegas.**
2. Mirá el reporte de `verificar.sh`.
3. Probá abrir el repositorio desde **otra** máquina: si funciona, la caché
   local está corrupta. No borres la caché de la máquina donde se manifiesta
   el problema.
4. Revisá archivos de tamaño cero y con marcas de tiempo raras.
5. Como último recurso, se pueden retirar los índices más recientes (los que
   empiezan por `x`) en orden inverso de fecha, para volver el repositorio a
   un estado anterior. **Con cautela.**

Upstream advierte: *"it's generally not recommended to attempt fixes
recommended to other users even for possibly similar issues, since all data
corruption cases are unique."*

---

## 11. Rendimiento: cómo dimensionar

### Memoria

**Upstream no pública requisitos mínimos oficiales.** No los inventamos.

Lo que sí se puede verificar en el código fuente
(`cli/command_repository_connect.go`): por defecto Kopia configura cachés de
**5000 MB de contenido** y **5000 MB de metadatos**. Ese es el presupuesto que
el proceso se propone usar.

Reducirlo:

```bash
kopia cache set --content-cache-size-mb=1024
kopia cache set --metadata-cache-size-mb=256
```

Recomendación de Hefesto para una Pyme: **2 GB de RAM** para el servidor de
repositorios. **Pendiente de medición real**
(`07-PRUEBAS-DE-ACEPTACION.md`).

### CPU

Upstream: los dos culpables son la **compresión** y el **paralelismo**.

```bash
kopia policy set --global --max-parallel-snapshots=1
kopia policy set --global --max-parallel-file-reads=2
```

Si la máquina va justa de memoria, `s2`, `deflate` y `gzip` son los algoritmos
másрайон módicos según upstream. Para archivos grandes, todos usan similar.

### Disco

El caché local crece hasta sus límites. Montalo en un disco con espacio, no en
la raíz del sistema.

### Dimensionar el repositorio

Kopia deduplica, así que **no podés multiplicar simplemente**. Como guía
operativa:

- **Recuperación completa**: imposible de calcular con certeza. Medí el primer
  snapshot real y sumá los increments diarios observados durante un mes.
- **Crecimiento**: mirá el delta del volumen entre dos snapshots.
- **Presupuesto**: dejar un margen de 30–50% sobre lo observado.

> **Regla práctica:** entre el 60% y el 80% de ocupación del bucket, las
> operaciones se ponen caras y hay que empezar a pensar en una política de
> niveles de almacenamiento. Upstream tiene una guía de *storage tiers*.

## Fuentes

- Verificación y corrupción: <https://kopia.io/docs/advanced/consistency/>
- Mantenimiento: <https://kopia.io/docs/advanced/maintenance/>
- Ransomware: <https://kopia.io/docs/advanced/ransomware/>
- Montar: <https://kopia.io/docs/mounting/>
- FAQ: <https://kopia.io/docs/faqs/>
- Almacenamiento: <https://kopia.io/docs/repositories/>
- Repository Server: <https://kopia.io/docs/repository-server/>
- Cachés por defecto: `cli/command_repository_connect.go`,
  <https://github.com/kopia/kopia/blob/master/cli/command_repository_connect.go>