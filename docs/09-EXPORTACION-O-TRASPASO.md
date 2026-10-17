# 09 — Exportación y traspaso

Este documento cubre tres cosas distintas, y conviene no mezclarlas:

1. **Exportar datos** de un repositorio Kopia a otro formato.
2. **Traspasar la operación** a otro proveedor de servicios o a otro técnico.
3. **Migrar de un proveedor de almacenamiento a otro.**

---

## 1. Exportar datos

### La verdad de fondo

> **Kopia no tiene comando de exportación a un formato abierto tipo "archivado".**
> El repositorio es un almacén de blobs cifrados y deduplicados **en el formato
> propietario de Kopia**. No es un `.tar`, no es un ZIP, no es un formato que
> otro programa pueda leer.

La única forma de sacar datos es **restaurarlos**. Eso es todo.

### Opciones reales de salida

| Destino | Método | Notas |
|---|---|---|
| Directorio local / NAS | `kopia snapshot restore <id> <destino>` | La vía normal |
| Un archivo suelto | `kopia snapshot restore <id> <destino> <subruta>` | Para extraer un archivo |
| Explorar sin copiar | `kopia mount <id> <punto>` | Upstream recomienda montar para restaurar |
| Volcado de base de datos | El **volcado** de la base, que ya es un formato estándar | Postgres, MySQL, Mongo |

### Volcados de base de datos: estos sí son formatos abiertos

Si el cliente tiene una base de datos, **el respaldo de verdad es el volcado**,
y ese archivo se puede leer con cualquier herramienta:

| Motor | Comando | Formato de salida |
|---|---|---|
| PostgreSQL | `pg_dump` | SQL plano, **custom** (`-Fc`) o **directory** (`-Fd`) |
| MySQL / MariaDB | `mysqldump` | SQL plano |
| MongoDB | `mongodump` | BSON, que **sí** se puede leer con herramientas estándar |

**Este kit no incluye recetas de base de datos.** Kopia no habla SQL y no hay
Supabase ni ningún motor relacional en juego. Si el proyecto necesita respaldo
de base de datos, se cotiza aparte.

### Un CSV exportado NO es una sincronización

Esto aplica a **todos** los productos y hay que decirlo con todas las letras:

> **Exportar un CSV es una foto, no una copia de seguridad.**

- Es una **instantánea de un momento**.
- No se actualiza solo.
- No tiene historial.
- Si alguien edita el CSV, no hay forma de saber qué cambió.
- No se puede verificar su integridad contra nada.

Un CSV que sale de un sistema el día lunes y nunca más es **un archivo**, no un
respaldo. **Dilo cuando el cliente pida "exportar los datos" pensando que eso
lo protege.**

### ¿Kopia implementa algún conector?

**No.** Kopia es un motor de respaldo de archivos. No tiene conector a Odoo,
ni a ningún ERP, ni API de sincronización. Si el cliente pide eso, es un
proyecto de integración aparte.

---

## 2. Traspaso de la operación a otro proveedor o a otro técnico

### Lo que hay que entregar

| Elemento | Dónde está | Crítico |
|---|---|---|
| Clave del repositorio | Gestor de contraseñas | **SÍ — es lo único irrecuperable** |
| Credenciales del bucket | Gestor de contraseñas | Sí |
| `KOPIA_BIND_HOST` y puertos | `compose.yaml` | Sí |
| Variables del `.env` | Gestor de contraseñas | Sí |
| Lista de usuarios del servidor | `kopia server user list` | Sí |
| Lista de orígenes y rutas | `kopia snapshot list --all` | Sí |
| Política de retención | `kopia policy show --global` | Sí |
| Propietario del mantenimiento | `kopia maintenance info` | Sí |
| **Este kit completo** | Repositorio de Hefesto | Sí |

### Procedimiento de traspaso

1. **Actualizá la custodia de la clave.** Antes que cualquier otra cosa.
2. Documentá la configuración ejecutando los comandos de la tabla.
3. Entregá el kit y las notas de firewall/DNS/proxy.
4. **Probá la recuperación desde cero** con el equipo entrante. Si no pueden
   llegar a `kopia snapshot list`, el traspaso no está hecho.
5. Recién después, cambiá las credenciales administrativas.

> Regla de oro del traspaso: **el que entra tiene que poder restaurar antes de
> que el que sale cambie la contraseña de nada.**

### Si el traspaso incluye cambio de personas

Hay que decidir explícitamente:

| Decisión | Consecuencia |
|---|---|
| ¿Quién guarda la clave del repositorio? | Si nadie, el servicio se muere |
| ¿Quién es dueño del bucket? | Si el anterior se va y era suyo, hay que migrar |
| ¿Quién corre el mantenimiento? | Si nadie, el repositorio crece |
| ¿Quién recibe las alertas? | Si nadie, nadie sabe que falló |

Estas cuatro preguntas se responden **por escrito**, antes de que la persona se
vaya.

---

## 3. Migración de almacenamiento

Cambiar de proveedor de bucket es posible pero **no es un cambio trivial**.

### ¿Es posible?

Sí. El repositorio es un conjunto de blobs. Se puede copiar el contenido del
bucket antiguo al nuevo y reconectar.

### Riesgos reales

| Riesgo | Detalle |
|---|---|
| **Reescritura de todos los datos** | Es la opción más simple y la más cara: agrega una copia completa. Upstream lo menciona como alternativa a una migración directa |
| **Coste de egreso** | Sacar los datos del proveedor viejo cuesta dinero. En AWS, el egreso desde S3 es de los más caros del mercado. Upstream cita `$0.09 por GB descargado` |
| **Restricciones de credenciales** | Si el bucket viejo usa claves sin permiso de borrado, la migración se complica |
| **Pérdida de Object Lock** | Si el destino no soporta Object Lock, se pierde la protección |
| **Cambio de proveedor S3-compatible** | Los endpoints y las políticas de acceso cambian |

### Procedimiento recomendado

1. **Medir el tamaño real** del repositorio.
2. **Calcular el egreso** del proveedor actual.
3. **Crear el repositorio nuevo** con las claves restringidas correctas.
4. Copiar los blobs con la herramienta del proveedor (`aws s3 sync`,
   `rclone sync`, `gsutil rsync`, `az storage blob copy-batch`).
5. `kopia repository connect` al destino nuevo.
6. `kopia snapshot verify --verify-files-percent=100`.
7. Recién ahí, sacar las credenciales del origen viejo.

> **`rclone sync` entre proveedores**: ojo, la integración de Kopia con rclone
> está marcada como **experimental** por upstream. Usar `rclone` **por fuera**
> para copiar blobs es otra cosa y no es lo mismo.

### Opción de bajo costo: `aws s3 sync`

```bash
aws s3 sync s3://bucket-viejo s3://bucket-nuevo --no-progress
```

Soporta directamente el traspaso entre proveedores S3 compatibles. Cobra los
costos de egreso del origen.

---

## 4. Dejar de usar el servicio

### Qué pasa con los datos

**No se borran automáticamente.** Kopia no tiene un "borrado tras X días sin
pago". Los datos se quedan en el bucket hasta que alguien los borre, y eso es
responsabilidad de quien controla el bucket.

Si el cliente se va, hay que:

1. **Restaurar los datos.** No «borrar el servicio»: restaurar.
2. Entregar un volcado o una copia final de lo importante.
3. Documentar cómo volver a levantar el servicio si cambia de opinión.

### Cómo volver a levantar el servicio más adelante

Es fácil, y para eso sirve la documentación:

1. Bucket intacto.
2. Clave del repositorio guardada.
3. Instalar Kopia y conectar.
4. `kopia snapshot list --all`.

Procedimiento completo: `scripts/restaurar-desde-cero.md`.

---

## 5. Connector implementado vs. guía de integración

Como lo pida explícitamente el contrato de los kits:

| Tipo | Estado en este kit |
|---|---|
| **Conector implementado a Odoo u otro ERP** | **No existe.** Kopia no tiene ninguna integración con sistemas de gestión |
| **Conector a una base de datos** | **No existe.** Kopia no habla SQL |
| **Integración con Coolify** | **Sí**, y es real: el kit se despliega como recurso Docker Compose |
| **Sincronización automática de datos a otro sistema** | **No existe.** Kopia es un almacén de instantáneas, no un pipeline de datos |
| **Exportación a formato estándar** | **Solo vía restauración.** No hay formato de exportación nativo |
| **Volcados de base de datos como formato interoperable** | **Sí**, pero los genera el motor de base de datos, no Kopia |

**Nunca vender un CSV como sincronización.** Y nunca vender "integración con
tu ERP" cuando lo que hay es un respaldo de archivos.

## Fuentes

- Montar y restaurar: <https://kopia.io/docs/mounting/>
- Almacenamiento y migración: <https://kopia.io/docs/repositories/>
- Coste de egreso citado por upstream (AWS S3):
  <https://kopia.io/docs/advanced/consistency/>
- Rclone experimental: <https://kopia.io/docs/repositories/#rclone>
- Recuperación desde cero: `scripts/restaurar-desde-cero.md` de este kit
- Alcance comercial: `08-SERVICIOS-COMERCIALES.md` de este kit