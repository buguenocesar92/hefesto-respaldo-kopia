# 08 — Servicios comerciales

Este documento es interno de Hefesto. Define qué se vende, a quién le sirve,
qué margen hay y **qué no se puede prometer**.

---

## 1. Por qué este producto es vendible

El catálogo de Hefesto tiene herramientas que **necesitan** respaldo y **ninguna
que respalde**. Este kit abre un rubro que, además, tiene tres características
que las demás líneas no tienen:

1. **Es recurrente.** Un respaldo es un contrato mensual. Las demás líneas son
   proyectos de una vez.
2. **El dolor es real y urgente.** Un cliente que perdió datos no discute
   precios.
3. **La venta se apoya en una evidencia, no en una promesa.** Kopia trae la
   herramienta de verificación, y Hefesto la pone en un informe mensual. Eso es
   algo que casi nadie en Chile le está haciendo a una Pyme.

### El argumento de venta

> **Un respaldo que nunca se probó es una hipótesis, no un respaldo.**

Casi todo el mundo tiene "copias de seguridad". Muy poca gente restauró alguna
vez. El cliente no quiere saber que tenés respaldos: quiere saber que **si le
borran todo mañana, puede trabajar el jueves**.

Kopia lo dice mejor que nadie:

> *"The gold standard for testing the validity of backups is to simply restore
> the snapshot; if restore is successful, then the backup is valid."*
> — <https://kopia.io/docs/advanced/consistency/>

**Ese es el producto:** no guardar archivos, sino **demostrar** que se
recuperan.

---

## 2. A quién le sirve

| Segmento | Dolor | Encaje |
|---|---|---|
| Pyme de servicios (estudios, anticorretes, clínicas) | Datos en un notebook o un NAS | **Alto.** El respaldo es manual o no existe |
| Agencias con muchos proyectos | Un disco perdido es perder clientes | **Muy alto** |
| Empresa con servidor propio y sin IT | Nadie sabe si el respaldo funciona | **Muy alto.** Esse es el nicho exacto |
| E-commerce pequeño | Volumen de datos creciente, copias a mano | **Alto** |
| Desarrollador que vende servidores | Necesita resale capacidad | **Medio** |

### Encaje bajo

- Empresa con equipo de TI y política de respaldo ya resuelta.
- Cliente que necesita respaldo **de imágenes de disco completas**. Esto no lo
  cubre Kopia.
- Grande con almacenamiento propio y cumplimiento ya auditado.

---

## 3. Qué se puede vender

### 3.1 Plan base — "Respaldo gestionado"

| Incluye | Detalle |
|---|---|
| Servidor de repositorios | Gestionado por Hefesto, en loopback o tras proxy TLS |
| Bucket o NAS configurado | Con clave de aplicación dedicada, sin permiso de borrado |
| Política de retención | Según el perfil del cliente |
| Respaldo programado | Diario, con ventana acordada |
| Verificación diaria | `snapshot verify --verify-files-percent=1` |
| **Informe mensual** | Instantáneas, errores, crecimiento, estado del mantenimiento |
| Alertas | Si una corrida falla o el propietario del mantenimiento se cae |

**Lo que el cliente recibe:** un informe que dice "su respaldo del martes se
verificó y se recuperó correctamente". Eso es lo que se vende.

### 3.2 Plan ampliado — "Respaldo con prueba de restauración"

Todo lo anterior, más:

- Verificación mensual al **100%**: descarga, descifra y comprueba todos los
  archivos.
- **Restauración de prueba real** de un subconjunto, con informe.
- La prueba de recuperación desde cero, al menos una vez al año, documentada.

Este es el plan con más margen y el que mejor se vende, porque es el que nadie
más hace.

### 3.3 Servicio puntual — "Prueba de recuperación"

Un proyecto único, sin contrato recurrente:

- Se levanta un entorno aislado.
- Se restaura desde el repositorio.
- Se documenta qué se recuperó, cuánto tardó y qué faltó.

**Este es el producto de entrada.** Es fácil de vender ("¿cuánto tardarían en
volver a funcionar si pierden el servidor?") y abre la puerta al contrato
mensual.

---

## 4. Alcance técnico del servicio

### Qué incluye el soporte

- Configuración del repositorio y del bucket.
- Alta de usuarios del servidor de repositorios.
- Programación de respaldos.
- Monitoreo y alertas.
- Verificación e informes.
- Acompañamiento en la **primera** restauración.
- Guía de **custodia de la contraseña** y de las pruebas trimestrales.

### Qué NO incluye (o se cotiza aparte)

| No incluye | Por qué |
|---|---|
| Restauración de sistemas operativos completos | Kopia no lo hace |
| Migración de bases de datos | Necesita conocimiento de la aplicación |
| Respaldo de SaaS de terceros | Los datos del cliente están en el proveedor |
| Cumplimiento normativo específico | Requiere análisis legal |
| Soporte 24/7 | Sin acuerdo |
| Auditorías externas | Es otro servicio |

---

## 5. Lo que NO se puede prometer

Esta es la sección más importante del documento. **Lo que se promete tiene que
ser exactamente lo que el producto hace.**

### 5.1 No es una imagen de disco

> Kopia respalda **archivos y directorios**. No el sistema operativo.

Si el cliente quiere restaurar un servidor entero, hay que decirlo de entrada.
Esto no lo hace y no hay configuración que lo cambie.

**Frase para el cliente:** *"Restauramos sus datos. La reinstalación del
sistema la hacemos aparte, y normalmente toma una hora."*

### 5.2 No hay garantía de que los datos se recuperen

Kopia se distribuye **"AS IS", sin garantía de ningún tipo** (Apache-2.0).
Además, el propio upstream advierte que:

- Un sistema de archivos sin semántica POSIX completa puede perder datos.
- El bit rot puede pasar.
- La corrupción "es rara pero ocurre".

**Lo que sí se puede prometer:** que se hizo todo lo razonablemente posible,
que se verificó, y que se entregó un informe. **Lo que no:** que los datos
siempre estarán ahí.

### 5.3 No hay aislamiento total entre clientes

Si Hefesto opera un servidor compartido:

- Cada cliente ve solo sus propias instantáneas y políticas.
- **El contenido no está aislado por deduplicación.** Upstream: *"Only snapshot
  and policy manifests are access-controlled, not the underlying contents."*
- Un cliente autenticado puede escribir contenido nuevo al repositorio.
- Un cliente puede leer la política global.

**No prometas multi-tenancy.** Ofrecé un servidor por cliente, o decí
claramente que el aislamiento es de índices.

### 5.4 La clave del repositorio es irrecuperable

> **Si el cliente pierde la clave, los respaldos son inservibles aunque los datos
> estén intactos.**

Upstream: *"There is absolutely no way to restore any of your backed up files
from a repository if you forget your password!"*

Esto hay que contractualizar: la custodia de la clave es **del cliente**.
Hefesto puede ayudar con el proceso, pero si se pierde, el servicio no puede
hacer nada.

### 5.5 No se recomienda contra ransomware por sí solo

Se puede configurar una protección muy buena (claves restringidas, Object
Lock), pero requiere:

- Configurar el bucket.
- Restaurar a un segundo bucket.
- Y aun así upstream advierte que un ransomware lento puede dejar **muchas**
  instantáneas modificadas, sin ninguna que represente un estado bueno.

**Frase honesta:** *"Estamos protegidos contra el ransomware que busca las llaves
para borrar los respaldos. No estamos protegidos contra un atacante
determinado."*

### 5.6 Los backends experimentales

`rclone` y `gdrive` están marcados como experimentales por upstream. **No se
venden.**

### 5.7 Kopia no habla SQL

Kopia no tiene motor de base de datos. **Supabase no aplica y no se menciona.**

Si el cliente tiene una base de datos, hay que:

1. Configurar el volcado de esa base (`pg_dump`, `mysqldump`).
2. Respaldar **el volcado**, no el volumen crudo.

Eso es trabajo adicional, cotizable aparte.

---

## 6. Modelo de precios (orientativo)

No es una lista de precios: es la estructura que conviene defender.

| Concepto | Base de cálculo |
|---|---|
| Servicio base | Fee mensual por cliente + costo de almacenamiento del cliente |
| Volumen | TB Storage + requests + egreso |
| Prueba de recuperación | Proyecto único |
| Ampliación de retención | Se sube el uso de almacenamiento |
| Migración de proveedor | Proyecto |
| Soporte fuera de horario | Fee adicional |

**El margen está en la gestión y en la verificación**, no en el
almacenamiento. El almacenamiento se factura casi al costo: es lo que el
cliente ve en su propia cuenta del proveedor.

---

## 7. Operación: qué hay que mirar siempre

| Señal | Por qué importa |
|---|---|
| `kopia maintenance info` → owner unexpected | Si no hay propietario, no hay mantenimiento y el repositorio crece |
| Último `.completo` más viejo que X horas | El respaldo automático se cayó |
| Código de salida `1` de `verificar.sh` | Integridad comprometida |
| Crecimiento anormal del bucket | Filtración, ransomware o política mal puesta |
| Desfase de reloj | Upstream lo lista entre las causas de corrupción |
| El cliente no tiene la clave en su gestor | **El riesgo número uno** |

### El tablero mínimo mensual

Un informe con:

1. Instantáneas creadas y con marca `.completo`.
2. Resultado de la verificación.
3. Tamaño del repositorio y variación mensual.
4. Estado del mantenimiento.
5. Resultado de la prueba de restauración.
6. Riesgos abiertos, incluido si el cliente tiene la clave.

---

## 8. Checklist antes de firmar

- [ ] ¿El cliente entendió que **no** es una imagen de disco?
- [ ] ¿Tiene claro quién guarda la clave del repositorio?
- [ ] ¿Está por escrito que la custodia es del cliente?
- [ ] ¿Se acordó la ventana de respaldo?
- [ ] ¿Se acordó la política de retención?
- [ ] ¿Se acordó qué pasa si el cliente deja de pagar? (**No se borran datos
      automáticamente. Se factura el mes y se avisa.**)
- [ ] ¿Se revisó que el bucket no tiene clave raíz?
- [ ] ¿Se entendió el límite de aislamiento si hay varios clientes?

---

## Fuentes

- Verificación: <https://kopia.io/docs/advanced/consistency/>
- Repository Server y aislamiento: <https://kopia.io/docs/repository-server/>
- Ransomware: <https://kopia.io/docs/advanced/ransomware/>
- FAQ: <https://kopia.io/docs/faqs/>
- Licencia Apache-2.0: <https://www.apache.org/licenses/LICENSE-2.0>
- Licencias y límites: `LICENCIAS.md` de este kit
- Pruebas pendientes: `docs/07-PRUEBAS-DE-ACEPTACION.md`