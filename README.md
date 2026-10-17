# Hefesto Studio — Kit de despliegue: Respaldo gestionado con Kopia

> **Estado del kit: `kit preparado`.**
> Los archivos de este kit están escritos y revisados contra la documentación
> oficial de Kopia y contra el código fuente del proyecto. **No se ejecutó
> Docker, no se creó un repositorio y no se restorationó nada** en el entorno
> donde se construyó el kit. Todo lo que esté marcado como pendiente de prueba
> en `docs/07-PRUEBAS-DE-ACEPTACION.md` sigue pendiente. No lo tomes como
> verificado.

---

## Qué es esto

Un kit de despliegue de **[Kopia](https://kopia.io/)**, la herramienta open
source de respaldos cifrados y deduplicados, en modo **Kopia Repository
Server**: un servicio que centraliza el acceso al repositorio para que los
clientes se autentiquen contra él **sin conocer las credenciales del
almacenamiento**.

No es un producto de licencia. Se vende como **servicio recurrente**: copias de
seguridad gestionadas, con **prueba de restauración** incluida.

### Por qué este kit existe en el catálogo de Hefesto

El catálogo de Hefesto tiene varias herramientas que **necesitan** respaldarse y
ninguna que se dedique a **respaldar**. Este kit cubre ese hueco, y cubre el más
vendido de la línea, porque tiene tres características que las otras no tienen:

1. **Es recurrente, no único.** Un respaldo es un contrato mensual. Un
   despliegue es un proyecto de una vez.
2. **Tiene una prueba de aceptación que la competencia informal no hace:**
   verificar que los datos realmente se pueden recuperar. Ver más abajo.
3. **Su riesgo principal es de gestión, no de software.** No falla por una
   actualización: falla porque nadie probó la contraseña o porque nadie miró el
   mantenimiento. Eso es trabajo de Hefesto, no del cliente.

---

## La idea que sostiene la venta

> **Un respaldo que nunca se probó es una hipótesis, no un respaldo.**

Casi todo el mundo tiene "copias de seguridad". Muy poca gente ha restaurado
alguna vez. El diferencial de este servicio no es guardar archivos: es
**demostrar, con evidencia y en un informe, que los archivos se recuperan**.

Kopia trae la herramienta para eso y hasta el criterio, textual:

> *"The gold standard for testing the validity of backups is to simply restore
> the snapshot; if restore is successful, then the backup is valid."*
> — [kopia.io/docs/advanced/consistency](https://kopia.io/docs/advanced/consistency/)

---

## Alcance y límites (léelos antes de vender)

### Lo que este kit SÍ hace

- Levanta un Kopia Repository Server con versión fijada por digest.
- Crea el repositorio sobre S3/compatible, Azure, B2, GCS, WebDAV, SFTP,
  disco local o NAS.
- Fija una política de retención y designa al propietario del mantenimiento.
- Toma instantáneas con registro, manifiesto y SHA-256.
- **Verifica la integridad del repositorio de verdad**, con código de salida
  para monitoreo.
- Restaura con validaciones, sin sobrescribir nada y dejando el servicio
  detenido.
- Documenta el procedimiento de recuperación desde cero.

### Lo que este kit NO hace, y hay que decirlo al cliente

| No lo hace | Por qué |
|---|---|
| **No respalda el sistema operativo.** | Kopia respalda archivos y directorios. No hay kernel, ni paquetes, ni usuarios, ni cron. Si el cliente quiere clonar un servidor entero, necesita otra guía aparte. **No lo vendas como imagen de disco.** |
| **No usa base de datos.** | Kopia no tiene motor relacional. **Supabase no aplica** y no se menciona como opción. Si hay una base de datos, se respalda el **volcado** de esa base, no el volumen. |
| **No es multi-tenant.** | No hay aislamiento entre clientes más allá de los ACL del Repository Server, y aun así el contenido no está controlado por ACL (ver abajo). **No prometas aislamiento entre clientes.** |
| **No protege del ransomware por sí solo.** | Se puede configurar protección con claves restringidas y Object Lock, pero hay que hacerlo en el bucket. Ver `docs/05`. |
| **No verifica TLS hacia atrás.** | Nunca se desactiva la verificación TLS del backend de almacenamiento en este kit, y no debe hacerse. |

### El límite de seguridad que hay que saber sí o sí

En modo Repository Server, Kopia controla el acceso a los **manifiestos**
(listas de instantáneas y políticas), **no al contenido**:

> *"Only snapshot and policy manifests are access-controlled, not the
> underlying contents."*
> — [kopia.io/docs/repository-server](https://kopia.io/docs/repository-server/)

Es decir: los índices están separados; los blobs de contenido se comparten y se
deduplican entre usuarios. Quien conozca el ID de un objeto puede restaurarlo.
Upstream considera inviable adivinar esos identificadores. Para endurecer el
esquema existen los ACL (`kopia server acl enable`).

---

## Contenido del paquete

```
hefesto-respaldo-kopia/
├── README.md                     Este archivo
├── compose.yaml                  Kopia Repository Server, puerto en loopback
├── compose.tls.yaml              Override para exponer con TLS tras un proxy
├── .env.example                  Sin secretos. Con las obligatorias marcadas
├── .gitignore
├── VERSION.md                    Versiones exactas, digest y cómo se fijaron
├── LICENCIAS.md                  Licencia de cada componente
├── config/
│   └── README.md                 Certificados TLS
├── scripts/
│   ├── lib.sh                    Funciones compartidas
│   ├── crear-repositorio.sh      Crea el repo, fija política y mantenimiento
│   ├── respaldar.sh              Snapshot + manifiesto + SHA-256
│   ├── verificar.sh              Verificación real, con código de salida
│   ├── restaurar.sh              Restauración validada y segura
│   └── restaurar-desde-cero.md   Procedimiento de desastre
├── ejemplos/                     Plantillas marcadas, sin secretos
└── docs/                         Los 10 documentos del kit
```

## Requisitos

- Un servidor con **Docker Engine** y el plugin **Docker Compose v2**.
- Acceso al almacenamiento elegido (bucket, NAS o disco) **creado y pagado por
  vos**: Kopia no lo provisiona.
- **2 GB de RAM** como punto de partida para el servidor de repositorios.
  Upstream **no publica requisitos mínimos oficiales**; este número es una
  recomendación de Hefesto, no un dato de upstream. Ver
  `docs/07-PRUEBAS-DE-ACEPTACION.md`.

---

## Inicio rápido

```bash
# 1. Preparar
cp .env.example .env
chmod +x scripts/*.sh
$EDITOR .env          # generar los secretos con openssl, ver .env.example

# 2. Crear el repositorio y la política (UNA vez, antes de levantar el servidor)
./scripts/crear-repositorio.sh

# 3. Levantar el servidor de repositorios
docker compose up -d
docker compose ps     # esperá a que diga "healthy"

# 4. Dar de alta el primer cliente
docker compose exec kopia /bin/kopia server user add USUARIO@SERVIDOR

# 5. Verificar
./scripts/verificar.sh
```

El orden importa: **el servidor no arranca si el repositorio no existe**.
Upstream lo dice en la guía del Repository Server.

Procedimiento completo paso a paso: `docs/01-INSTALACION-DOCKER.md`.

### Permisos de los scripts

Los archivos llegan sin permiso de ejecución si los descomprimís en Windows o
en un volumen que no conserva el bit de Unix. Antes de correrlos:

```bash
chmod +x scripts/*.sh
```

---

## Configuración sensible

| Variable | Por qué importa |
|---|---|
| `KOPIA_PASSWORD` | **La clave del repositorio.** Ver más abajo. |
| `KOPIA_BIND_HOST` | Déjalo en `127.0.0.1` salvo que tengas TLS y proxy. |
| `KOPIA_IDENTITY_HOST` / `KOPIA_IDENTITY_USER` | Fijan el nombre del origen. Si cambian, el historial se parte en dos. |

---

## El riesgo número uno: la contraseña

> **La contraseña del repositorio es la única clave que descifra los respaldos.**
> Si se pierde, los respaldos son inservibles **aunque los datos estén
> intactos** en el bucket. No hay recuperación, no hay soporte, no hay
> excepción.

Upstream lo dice sin rodeos:

> *"There is absolutely no way to restore any of your backed up files from a
> repository if you forget your password!"*
> — [kopia.io/docs/getting-started](https://kopia.io/docs/getting-started/)

Y agregan un detalle que suele escaparse: se **puede** cambiar la contraseña,
pero **solo estando conectado al repositorio**. Si la olvidaste y no estás
conectado, no hay reset.

### Cómo la custodia Hefesto

1. Clave en un gestor de contraseñas, **fuera del servidor**.
2. Sobre sellada entregada al cliente (opcional, para Pymes grandes).
3. **Prueba trimestral de custodia**: alguien que no administra el servidor
   tiene que poder abrir una máquina limpia y llegar a listar instantáneas.
   Si no puede, la custodia es de mentira.
4. La clave **no** se reutiliza como contraseña del bucket ni de la interfaz.

Detalle completo: `docs/05-RESPALDOS-Y-RESTAURACION.md`.

---

## Documentación

| Documento | De qué trata |
|---|---|
| `docs/01-INSTALACION-DOCKER.md` | Paso a paso en Ubuntu/Debian limpio |
| `docs/02-INSTALACION-COOLIFY.md` | Despliegue como recurso Docker Compose en Coolify |
| `docs/03-VARIABLES-Y-COMO-OBTENERLAS.md` | Cada variable, de dónde sale, qué pasa si cambia |
| `docs/04-PRIMERA-CUENTA-Y-USUARIOS.md` | Primer usuario, ACL y modelo de permisos real |
| `docs/05-RESPALDOS-Y-RESTAURACION.md` | Copia coherente, verificación, identidad del origen, ransomware |
| `docs/06-ACTUALIZACIONES-Y-REVERSION.md` | Cómo actualizar y cómo volver atrás |
| `docs/07-PRUEBAS-DE-ACEPTACION.md` | **Qué se verificó de verdad y qué no** |
| `docs/08-SERVICIOS-COMERCIALES.md` | A quién se le vende y qué no se puede prometer |
| `docs/09-EXPORTACION-O-TRASPASO.md` | Exportar datos y traspasar a otro proveedor |
| `docs/10-LICENCIAS-Y-FUENTES.md` | Licencias y fuentes |

---

## Qué es y qué no es este kit

- **Es un kit de despliegue**, no el código de Kopia. Kopia no se compila ni se
  modifica acá: se usa la imagen oficial `kopia/kopia`.
- **El código propio de Hefesto son los `scripts/`**: cinco scripts de shell
  que orquestan `kopia` y agregan las garantías que la CLI sola no da
  (manifiesto con SHA-256, marca de completado, validación de rutas de
  restauración, códigos de salida para monitoreo). Están bajo la licencia del
  estudio.
- **Lo que viene de upstream**: la imagen, el binario y toda la lógica de
  respaldo. Licencia **Apache-2.0**. Ver `LICENCIAS.md`.

---

## Qué queda pendiente

Todo lo siguiente está **pendiente de ejecución** y está detallado en
`docs/07-PRUEBAS-DE-ACEPTACION.md`:

- [ ] Levantar el compose en un servidor real y confirmar `healthy`.
- [ ] Crear un repositorio de prueba y una instantánea de prueba.
- [ ] Confirmar que el healthcheck responde con credenciales válidas.
- [ ] Probar `restaurar.sh` con un destino ocupado y confirmar que **rechaza**.
- [ ] Probar la restauración desde cero completa en una máquina nueva.
- [ ] Medir RAM y CPU reales con un volumen de datos de tamaño realista.
- [ ] Probar el flujo de Coolify y la emisión de certificados.
- [ ] Confirmar el comportamiento del mantenimiento cuando el propietario
      está apagado.