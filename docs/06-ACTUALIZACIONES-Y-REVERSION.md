# 06 — Actualizaciones y reversión

---

## Principio

**Kopia guarda los datos. La versión es solo software.** Una actualización de
versión, en principio, no cambia los datos. Pero "en principio" no es un plan.

> **Regla del kit:** antes de tocar un repositorio de cliente, se verifica el
> repositorio de cliente. Antes y después.

---

## 1. Cuándo actualizar

| Situación | ¿Actualizar? |
|---|---|
| Hay una versión con corrección de datos | **Sí, pronto.** Ejemplo: v0.23.1 arregla una condición de carrera capaz de causar pérdida de datos |
| Hay una corrección de seguridad | Sí, evaluando el impacto |
| Sale una versión con mejoras | No es urgente |
| El cliente está en plena operación y todo funciona | No |

**Nunca** apliques una versión nueva como parte de una venta sin avisar.

---

## 2. Verificar qué hay disponible

```powershell
# Último release estable (no prerelease, no draft)
Invoke-RestMethod 'https://api.github.com/repos/kopia/kopia/releases/latest' |
  Select-Object tag_name, published_at, prerelease, draft
```

```bash
# Ver los releases recientes en el navegador
# https://github.com/kopia/kopia/releases
```

Una versión es candidata solo si `prerelease = False` **y** `draft = False`.

### Leer las notas antes de decidir

Para cada versión, revisá:

1. ¿Hay una corrección de **pérdida de datos**? → Sube de prioridad.
2. ¿Hay cambios de **formato de repositorio**? → Requiere plan.
3. ¿Hay cambios **incompatibles** en configuración o flags? → Revisar `compose.yaml`.
4. ¿Hay una migración irreversible? → Ver más abajo.

---

## 3. Procedimiento de actualización

### Paso 0 — Respaldo del estado de control

Antes de nada, copiá lo que permite volver atrás:

```bash
# Copia de la configuración del servidor
docker compose down
mkdir -p ~/kopia-respaldo-$(date +%F)
cp .env ~/kopia-respaldo-$(date +%F)/
chmod 600 ~/kopia-respaldo-$(date +%F)/.env
docker compose up -d

# Copia del volumen de configuración del repositorio
docker run --rm \
  -v kopia-config:/origen:ro \
  -v ~/kopia-respaldo-$(date +%F):/destino \
  alpine tar czf /destino/repository.config.tar.gz -C /origen .
```

> Esto **no** es el respaldo de los datos. Es lo que te deja volver a
> reconstruir la conexión al repositorio sin adivinar.

### Paso 1 — Verificar ANTES

```bash
./scripts/verificar.sh --porcentaje 0
```

Si falla **antes** de actualizar, el problema no es la versión. No sigas.

### Paso 2 — Probar en un entorno paralelo (obligatorio para clientes)

Nunca actualices directo sobre producción:

```bash
# Copia de prueba del repositorio, en otro bucket
KOPIA_S3_BUCKET=mi-bucket-PRUEBA \
  ./scripts/crear-repositorio.sh
```

O, si querés probar la apertura del repositorio existente sin tocarlo:

```bash
KOPIA_PASSWORD='...' MODO=contenedor \
IMAGE_KOPIA=kopia/kopia:NUEVA_VERSION \
  ./scripts/verificar.sh --porcentaje 1
```

`IMAGE_KOPIA` permite probar otra versión sin editar `compose.yaml`.

### Paso 3 — Actualizar

1. Editá `VERSION.md` con la versión y la fecha.
2. Editá la línea `image:` de `compose.yaml` con la etiqueta y el **digest
   nuevo**.
3. Resolvé el digest:

   ```powershell
   $t = Invoke-RestMethod 'https://hub.docker.com/v2/repositories/kopia/kopia/tags/<VERSION>'
   $t.digest
   ```

4. Descargá y levantá:

   ```bash
   docker compose pull
   docker compose up -d
   docker compose ps          # esperar "healthy"
   ```

### Paso 4 — Verificar DESPUÉS

```bash
./scripts/verificar.sh --porcentaje 1
```

Y una restauración de prueba real de un archivo:

```bash
./scripts/restaurar.sh --listar
./scripts/restaurar.sh ID_INSTANTANEA /tmp/prueba
diff <archivo> <archivo-restaurado> && echo "OK"
rm -rf /tmp/prueba
```

### Paso 5 — Actualizar los clientes

Los clientes tienen su **propia conexión**. Actualizarlos es independiente:

```bash
# En cada cliente
docker pull kopia/kopia:<VERSION>
./scripts/verificar.sh --porcentaje 0
```

---

## 4. Revertir

Si algo sale mal:

```bash
# 1. Volver a la imagen anterior
$EDITOR compose.yaml       # cambiar image: a la versión anterior
docker compose pull
docker compose up -d
docker compose ps
```

```bash
# 2. Verificar
./scripts/verificar.sh --porcentaje 0
```

```bash
# 3. Si la configuración se corrompió, restaurar el volumen
docker compose down
docker run --rm \
  -v ~/kopia-respaldo-2026-10-16:/respaldo:ro \
  -v kopia-config:/destino \
  alpine sh -c 'rm -rf /destino/* && tar xzf /respaldo/repository.config.tar.gz -C /destino'
docker compose up -d
```

> **La reversión de configuración no revierte los datos.** Si la versión nueva
> migró el formato del repositorio, volver el binario no deshace la migración.

---

## 5. Qué migraciones no son reversibles

Esto hay que verificarlo leyendo las notas de cada versión. Hasta ahora, lo que
la documentación del proyecto señala:

### 1. Algoritmo de cifrado

El algoritmo de cifrado **se elige al crear el repositorio** y **no se puede
cambiar después**:

> *"Currently, encryption algorithms cannot be changed after a repository has
> been created."*
> — <https://kopia.io/docs/faqs/#how-do-i-enable-encryption>

Valores: `AES256-GCM-HMAC-SHA256` (por defecto) o
`CHACHA20-POLY1305-HMAC-SHA256`.

**Impacto:** si creaste el repositorio con una versión nueva que cambió el
algoritmo por defecto, ya no lo puedes cambiar. Solo la recreación del
repositorio lo haría, lo que implica restaurar todo.

### 2. Formato del repositorio

`kopia.repository` es el archivo de formato del repositorio. El propio manual
advierte de la tentación de "optimizar" ese archivo:

> *"If you don't understand what these settings are, do not change them because
> the default settings are the best settings."*
> — <https://kopia.io/docs/repositories/>

El hash, el splitter y el formato **se fijan al crear el repositorio**.

### 3. Object Lock

Si se habilita `Object Lock`, **no se puede desactivar**. Y las fechas de
retención **no se pueden reducir ni eliminar**. Upstream advierte que un
atacante podría usarlo para generar costos incontrolados. Ver
`05-RESPALDOS-Y-RESTAURACION.md`.

### 4. Cambio del propietario de mantenimiento

Se puede cambiar en cualquier momento, pero hay que tener en cuenta que el
anterior deja de correr mantenimiento de inmediato.

---

## 6. Actualizar en Coolify

En un recurso **Docker Compose**:

1. Actualizá la línea `image:` del compose.
2. Actualizá `VERSION.md`.
3. Botón **Redeploy**.
4. Revisá los logs y el estado de salud.

Los volúmenes con prefijo de proyecto se conservan en el redeploy. **Nunca uses
"Rebuild"+"Clear volumes"** sobre un repositorio de cliente.

---

## 7. Lista de verificación de actualización

- [ ] Leí las notas de la versión nueva.
- [ ] La versión no es prerelease ni draft.
- [ ] Copié el `.env` y el volumen `kopia-config`.
- [ ] Verifiqué el repositorio **antes** de actualizar (salida 0).
- [ ] Probé en un repositorio o entorno paralelo.
- [ ] Resolví y anoté el digest nuevo.
- [ ] Actualicé `VERSION.md`.
- [ ] Verifiqué **después** (salida 0).
- [ ] Hice una restauración de prueba de un archivo real.
- [ ] Actualicé los clientes.
- [ ] Confirmé que el propietario del mantenimiento sigue siendo el correcto.

## Fuentes

- Releases: <https://github.com/kopia/kopia/releases>
- Cifrado y cambios irreversibles: <https://kopia.io/docs/faqs/>
- Almacenamiento y opciones de creación: <https://kopia.io/docs/repositories/>
- Mantenimiento: <https://kopia.io/docs/advanced/maintenance/>
- Ransomware y Object Lock: <https://kopia.io/docs/advanced/ransomware/>