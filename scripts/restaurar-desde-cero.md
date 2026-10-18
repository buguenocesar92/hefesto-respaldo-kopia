# Restauración desde cero — el escenario de desastre

> **Este es el procedimiento que decide si el servicio es real.**
> Si la contraseña del repositorio se pierde, **no hay restauración**.
> Nada de lo que sigue funciona sin ella.

Este documento asume el peor escenario posible y el más frecuente en una Pyme:

> El servidor se perdió. Se quedó un disco quemado, un robo, una inundación o
> un borrado accidental. ElDominio no existe. El servidor no existe. **Solo
> quedan dos cosas: el almacenamiento (bucket, NAS, disco externo) y la
> contraseña del repositorio.**

---

## 0. Antes de necesitar esto

Las tres cosas que tienen que existir **fuera del servidor** son:

| # | Qué | Dónde vive | Cómo se pierde |
|---|---|---|---|
| 1 | **Contraseña del repositorio** | Gestor de contraseñas | Es la clave. Si se pierde, se pierden los respaldos. |
| 2 | **Credenciales del almacenamiento** | Gestor de contraseñas, con rotación periódica | Se puede regenerar, pero hay que saber *qué* almacenamiento es |
| 3 | **Dónde está cada cosa** | Documento de traspaso | Amnesia del técnico |

Si alguno de los tres no está por escrito y probado, **no hay plan de
recuperación**. Hay una intención.

### Prueba de custodia de la contraseña

Trimestralmente, alguien que **no** administrative el servidor debe poder
retirar la contraseña del gestor, abrir una máquina limpia y llegar al menos a
la etapa 4 (listar instantáneas). Si no puede, la custodia es teórica.

Cuidado con un detalle real de Kopia: **cambiar la contraseña exige estar
conectado al repositorio**. Upstream lo dice textualmente — si la olvidaste y
no estás conectado, no hay forma de restablecerla. Ver
<https://kopia.io/docs/faqs/#how-do-i-change-my-repository-password>.

---

## 1. Reunir (5 minutos)

Necesitás:

- La contraseña del repositorio (nunca por chat ni por correo).
- Un equipo con acceso a internet: un VPS nuevo, tu notebook, cualquier cosa.
- Las credenciales del bucket / NAS.
- La huella del certificado, **solo** si usaste `compose.tls.yaml`.

No necesitás: el servidor viejo, su disco, su sistema operativo.

---

## 2. Instalar Kopia en una máquina limpia

### Opción A — contenedor (recomendada, es lo que vende Hefesto)

```bash
mkdir ~/recuperacion-kopia && cd ~/recuperacion-kopia

# Imagen fijada a la misma version del kit. Si el repositorio se creo con
# otra version, abajo se explica el problema.
docker run --rm -it \
  --name kopia-recuperacion \
  -e KOPIA_PASSWORD \
  -v kopia-recuperacion-config:/app/config \
  -v kopia-recuperacion-cache:/app/cache \
  kopia/kopia:0.23.1@sha256:89fd95ee2942880ca00eae964266958a394421ddbdf69bca62e38afc55f5900e \
  --help
```

### Opción B — binario nativo

Según la plataforma, desde <https://github.com/kopia/kopia/releases>.

> **Sobre la versión:** los repositorios de Kopia se pueden abrir con versiones
> posteriores a la que los creó, pero no se debe asumir que una versión muy
> antigua abra un repositorio nuevo. Si el repositorio se creó con la versión
> fijada en `VERSION.md` (v0.23.1), usá esa misma versión. Es el camino sin
> sorpresas.

---

## 3. Conectar al repositorio (2 minutos)

El comando cambia según dónde vive el almacenamiento.

### Si el almacenamiento es S3 / compatible

```bash
docker run --rm -it --env KOPIA_PASSWORD \
  -v kopia-recuperacion-config:/app/config \
  -v kopia-recuperacion-cache:/app/cache \
  kopia/kopia:0.23.1@sha256:89fd95ee2942880ca00eae964266958a394421ddbdf69bca62e38afc55f5900e \
  repository connect s3 \
    --bucket=BUCKET \
    --endpoint=ENDPOINT \
    --region=REGION \
    --access-key=ACCESS_KEY \
    --secret-access-key=SECRET_KEY
```

Si usaste el motor `filesystem` (NAS o disco montado), reemplazá por:

```bash
    ... repository connect filesystem --path=/mnt/nas/kopia
```

Si usaste SFTP, WebDAV, B2, Azure o GCS, los flags están documentados en
<https://kopia.io/docs/repositories/> y son los mismos que usaste al crear el
repositorio (el resumen quedó en `manifiestos/repositorio-*.resumen.txt`).

### Sobre el hostname

En una máquina nueva, Kopia identifica el origen como
`usuario@servidor:/ruta`. Con el hostname distinto, **la máquina nueva aparece
como un origen sin historia**: no ve las instantáneas viejas como suyas y las
instantáneas anteriores dejan de ser purgadas.

Esto se arregla con los mismos flags de identidad del kit:

```bash
    ... repository connect s3 ... \
      --override-hostname=srv-respaldos \
      --override-username=hefesto
```

Usá **exactamente** los valores de `KOPIA_IDENTITY_HOST` y
`KOPIA_IDENTITY_USER` del `.env` original. Si no los anotaste, usá
`kopia snapshot list --all` para ver todos los orígenes con su
`usuario@servidor` real y reconstruí los valores.

---

## 4. Ver qué hay (el momento de la verdad)

```bash
    ... snapshot list --all
```

Si acá no aparece nada, y la contraseña era correcta, hay dos posibilidades
malas: la contraseña estaba mal, o el bucket no es el que pensabas. No sigas.

Si aparece, **anotá el ID** de la instantánea que querés restaurar. Es la
primera columna de la salida.

---

## 5. Verificar antes de confiar

No te saltes esto. Una restauración completa que falla a mitad es peor que no
empezar, porque te deja un directorio con apariencia de datos buenos.

```bash
# Verificación estructural completa (rápida, no descarga los archivos)
    ... snapshot verify --verify-files-percent=0

# Verificación profunda: descarga, descifra y descomprime el 100% de los
# archivos. Lento y consume ancho de banda, pero es la prueba real.
    ... snapshot verify --verify-files-percent=100 --file-parallelism=10
```

Upstream: *"If Kopia throws no errors while running this command, then your
snapshots/repositories are valid."*
Fuente: <https://kopia.io/docs/advanced/consistency/>

**Si la verificación profunda falla, no sigas con esa instantánea.** Probá con
una anterior, o usá el procedimiento de corrupción de la misma página.

---

## 6. Restaurar

```bash
    ... snapshot restore ID_DE_LA_INSTANTANEA /mnt/recuperacion
```

Para un archivo suelto en vez de todo:

```bash
    ... snapshot restore ID_INSTANTANEA /mnt/recuperacion ruta/dentro/del/snapshot
```

Si querés explorar antes de copiar nada — upstream dice que **montar es la vía
recomendada para restaurar**:

```bash
    ... mount ID_INSTANTANEA /mnt/montaje &
    ls -la /mnt/montaje/
    # ... copiás lo que necesites ...
    umount /mnt/montaje
```

`kopia mount` usa FUSE. En Docker eso requiere agregar `/dev/fuse` y `SYS_ADMIN`
a `docker run`; el compose del kit **no** los incluye a propósito. Para una
recuperación puntual se pueden agregar en la línea de comando.

---

## 7. Reconstruir el servidor

Recién ahora, con los datos en la mano:

1. Levanta el servidor nuevo (VPS en blanco, Ubuntu/Debian).
2. Instala la aplicación y sus dependencias.
3. **Deja la aplicación detenida.**
4. Copia los datos restaurados a su ubicación final.
5. Ajusta permisos y propietario de archivos.
6. Levanta la aplicación.
7. Revisa la aplicación: conexiones a base de datos, claves, permisos.

Ojo: **Kopia no respalda el sistema operativo.** No hay kernel, ni paquetes, ni
usuarios, ni cron, ni configuración del sistema en el respaldo. Solo archivos y
directorios. Si lo que el cliente quiere es clonar un servidor entero, esto no
es la herramienta y hay que decirlo de entrada.

---

## 8. Cerrar el incidente (no te saltes esto)

1. **Rota la contraseña del repositorio** si se cree que pudo filtrarse:

   ```bash
       ... repository change-password
   ```

2. Rota las credenciales del almacenamiento.
3. Crea un **repositorio nuevo y limpio**. Un repositorio que pasó por
   un incidente es un repositorio sospechoso: no se sabe qué más quedó escrito.
4. Copia los datos recuperados al repositorio nuevo.
5. Vuelve a verificar.
6. Documenta qué pasó, qué se perdió y cuánto tiempo tomó recuperar.

---

## Anexo — el escenario fácil: restaurar un solo archivo

Mucho más común que la pérdida total, y mucho más barato:

```bash
    ... snapshot list --all /ruta/del/origen
    ... ls -l ID_INSTANTANEA                    # ver el contenido
    ... snapshot restore ID_INSTANTANEA /tmp/prueba ruta/dentro
```

Y después, sin falta, `rm -rf /tmp/prueba`.

---

## Fuentes

- Verificación y corrupción: <https://kopia.io/docs/advanced/consistency/>
- Contraseña y recuperación: <https://kopia.io/docs/faqs/#how-do-i-change-my-repository-password>
- Montar: <https://kopia.io/docs/mounting/>
- Almacenamientos: <https://kopia.io/docs/repositories/>
- Servidor de repositorio: <https://kopia.io/docs/repository-server/>