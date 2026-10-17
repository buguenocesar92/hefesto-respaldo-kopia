# 04 — Primera cuenta, usuarios y modelo de permisos real

Este documento explica cómo queda el acceso al repositorio una vez montado el
servidor, **con los límites reales que impone Kopia**, no con los que uno
supone.

---

## 1. Hay tres cosas que se confunden seguido

| Cosa | Qué es | Dónde vive |
|---|---|---|
| **Clave del repositorio** | La que cifra y descifra los datos | El `.env` del servidor y el de cada cliente |
| **Cuenta de la interfaz** | La que abre la UI web y la API | `KOPIA_SERVER_USERNAME` / `KOPIA_SERVER_PASSWORD` |
| **Cuentas de cliente** | Las que usan las máquinas que respaldan | `kopia server user add usuario@servidor` |

Son tres capas distintas. Confundirlas es la causa número uno de «el respaldo
no conecta».

---

## 2. La primera cuenta: la del servidor

### 2.1 Generar la clave del repositorio

```bash
openssl rand -base64 48 | tr -d '\n=' ; echo
```

Va en `KOPIA_PASSWORD`. **Es la más importante de las tres.** Guardala en un
gestor de contraseñas antes de seguir.

### 2.2 Generar las contraseñas de la interfaz y del control

```bash
openssl rand -base64 32 | tr -d '\n=' ; echo   # KOPIA_SERVER_PASSWORD
openssl rand -base64 32 | tr -d '\n=' ; echo   # KOPIA_SERVER_CONTROL_PASSWORD
```

Van en el `.env`, con `chmod 600`.

### 2.3 Levantar

```bash
chmod 600 .env
docker compose up -d
docker compose ps        # esperar "healthy"
```

La UI queda en <http://127.0.0.1:51515> desde el propio servidor, o por túnel
SSH desde tu estación.

### 2.4 Iniciar sesión

Usuario `KOPIA_SERVER_USERNAME`, contraseña `KOPIA_SERVER_PASSWORD`.

> **Nunca** abras la UI desde un navegador que ya tenga sesión administrativa de
> otra cosa, y nunca la publiques en un enlace sin HTTPS. La UI permite
> administrar instantáneas, políticas y usuarios del repositorio.

---

## 3. Crear un usuario de cliente

El usuario de un cliente se identifica como **`usuario@servidor` en
minúsculas**, donde `servidor` es el hostname de la máquina del cliente **sin
sufijo de dominio**.

```bash
# 1. En la maquina cliente, averiguar el hostname
hostname
# -> srv-datos

# 2. En el servidor, crear el usuario
docker compose exec kopia /bin/kopia server user add cliente@srv-datos
```

Kopia pide la contraseña dos veces. **No se puede pasar por línea de comandos**,
y es a propósito: queda fuera del historial del shell.

### Las credenciales tardan en aplicarse

Upstream avisa:

> *"Updated user credentials will take effect in 5-10 minutes or when the
> server is restarted."*

Para no esperar:

```bash
docker compose exec kopia /bin/kopia server refresh \
  --address=http://127.0.0.1:51515 \
  --server-username=control-respaldos
```

O reiniciá el contenedor. En Linux también sirve `kill -SIGHUP` sobre el
proceso de kopia.

### Otros comandos

```bash
docker compose exec kopia /bin/kopia server user list
docker compose exec kopia /bin/kopia server user set cliente@srv-datos
docker compose exec kopia /bin/kopia server user delete cliente@srv-datos
```

---

## 4. Conectar el cliente

```bash
export KOPIA_PASSWORD='<clave del repositorio>'

kopia repository connect server \
  --url=https://respaldos.tudominio.cl:51515 \
  --server-cert-fingerprint=$HUELLA \
  --server-username=cliente@srv-datos \
  --server-password='<contraseña del usuario>' \
  --override-hostname=srv-datos \
  --override-username=cliente
```

**Los dos `--override` no son opcionales.** Sin ellos, si el hostname de la
máquina cambia, aparece un origen nuevo sin historial y las instantáneas viejas
dejan de purgarse. Ver `03-VARIABLES-Y-COMO-OBTENERLAS.md`.

### Detalle técnico

En el lado cliente, los flags `--server-username` y `--server-password` están
marcados como **ocultos** en el código fuente: son alias de
`--server-control-username` y `--server-control-password`, y leen las mismas
variables de entorno `KOPIA_SERVER_USERNAME` y `KOPIA_SERVER_PASSWORD`.
Verificado en `cli/command_server.go`.

---

## 5. El modelo de permisos REAL

Esta es la parte que hay que explicarle al cliente con todas sus letras.

### Qué sí está controlado

En modo Repository Server, cada usuario ve **solo sus propias instantáneas y
políticas**:

> *"In repository server mode, each user is limited to seeing their own
> snapshots and policy manifest without being able to access those from another
> user account."*

### Qué NO está controlado

Y acá viene lo importante:

> *"Only snapshot and policy manifests are access-controlled, **not the
> underlying contents**. If two users share the same file, it will be backed
> using identical content IDs. The consequence is that if a third user can
> guess the content ID of files in the repository, they can access the
> files."*

Traducción: **los índices están separados; los datos no.** La deduplicación es
global, y si dos usuarios tienen el mismo archivo se guarda una sola vez.

Upstream considera inviable adivinar un ID de objeto (128 o 256 bits), y el
riesgo se acepta. Para un servicio comercial, **decí esto al cliente** en vez
de vender "aislamiento total entre clientes".

### Lo que puede hacer CUALQUIER usuario autenticado

Por defecto, sin configurar ACL:

| Acción | Permitido |
|---|---|
| Leer y escribir sus propias políticas | Sí |
| Leer y escribir sus propias instantáneas | Sí |
| **Leer la política `global`** | **Sí** |
| Leer políticas de nivel host del propio host | Sí |
| Cambiar su propia contraseña | Sí |
| **Leer objetos si conoce su ID** | **Sí** |
| **Escribir contenido nuevo al repositorio** | **Sí** |

O sea: un usuario autenticado **no puede ver tus instantáneas**, pero **sí puede
consumir espacio** escribiendo contenido nuevo, y **sí puede leer la política
global**.

### Consecuencia entre clientes

Si Hefesto opera el servidor para varios clientes:

- Cada cliente ve solo sus propias instantáneas.
- **No hay aislamiento de los datosunderlying** por deduplicación.
- Un cliente puede escribir contenido nuevo y hacer crecer el repositorio.
- Un cliente puede leer la política global.

**No prometas multi-tenancy.** Es un servidor compartido con separación de
índices.

---

## 6. Endurecer con ACL

Kopia tiene un sistema de listas de acceso explícito. Activarlo instala las
reglas por defecto y permite ajustarlas.

```bash
# Instalar el conjunto de reglas por defecto
docker compose exec kopia /bin/kopia server acl enable

# Ver las reglas
docker compose exec kopia /bin/kopia server acl list
```

Salida típica (los identificadores cambian en cada repositorio):

```
id:c95e5a13b0b0fc874e550677f5e89262 user:*@* access:APPEND target:type=content
id:633f998af93e00c715e6417cb41df0af user:*@* access:READ  target:type=policy,policyType=global
id:de21ac7b55ec1d9cf939b4cb158cc85a user:*@* access:READ  target:type=policy,hostname=OWN_HOST,policyType=host
id:2314795d54060ab84cdc7fcb6e6953c8 user:*@* access:FULL target:type=policy,username=OWN_USER,hostname=OWN_HOST
id:0245e5bc1eca296e775e137a9587d09e user:*@* access:FULL target:type=snapshot,hostname=OWN_HOST,username=OWN_USER
id:fb043d9e77299e182e9297d0f4601d9c user:*@* access:FULL target:type=user,username=OWN_USER@OWN_HOST
```

### Niveles de acceso

| Nivel | Qué permite |
|---|---|
| `READ` | Leer, no escribir |
| `APPEND` | Leer y escribir, **no borrar** |
| `FULL` | Leer, escribir y borrar |

### Valores especiales

- `OWN_USER` → el usuario de la regla
- `OWN_HOST` → el hostname de la regla
- `*` → comodín

### Ejemplos

Dar a un administrador la posibilidad de gestionar usuarios:

```bash
docker compose exec kopia /bin/kopia server acl add \
  --user "admin@srv-central" \
  --access FULL --target type=user
```

Permitir que un usuario modifique la política global:

```bash
docker compose exec kopia /bin/kopia server acl add \
  --user "admin@srv-central" \
  --access FULL --target type=policy,policyType=global
```

Quitar la lectura de la política global a todos:

```bash
docker compose exec kopia /bin/kopia server acl remove \
  633f998af93e00c715e6417cb41df0af --delete
```

> `remove` y `remove --all` trabajan en **modo vista previa** y exigen
> `--delete` para confirmar. Revisá lo que vas a borrar.

### Modo heredado

Antes de Kopia v0.8 las reglas no eran configurables y se usaba un archivo
htpasswd. Ese método sigue soportado pero upstream recomienda `kopia server
user`. Este kit usa el método moderno.

---

## 7. Alta y baja de clientes

### Dar de alta

1. Averiguar el hostname en la máquina cliente.
2. `kopia server user add usuario@host`
3. Entregar al cliente: URL del servidor, nombre de usuario, contraseña **de ese
   usuario**, huella del certificado y **la clave del repositorio** (que
   necesita para cifrar sus datos).
4. El cliente conecta y verifica con `kopia snapshot list`.

### Dar de baja

1. `kopia server user delete usuario@host`
2. **El usuario deja de acceder de inmediato.**
3. **Sus instantáneas NO se borran.** Quedan en el repositorio hasta que el
   mantenimiento las purgue según la política de retención.

Si querés eliminarlas antes, hay que hacerlo con un cliente que ya tenga
acceso, o intervenir el origen. Ver `05-RESPALDOS-Y-RESTAURACION.md`.

---

## 8. Lista de verificación de seguridad

Antes de dar por cerrado el alta de un cliente:

- [ ] El puerto 51515 **no** está expuesto a internet sin TLS.
- [ ] La UI no se accede por HTTP plano fuera de localhost o túnel SSH.
- [ ] La clave del repositorio está en el gestor de contraseñas del cliente.
- [ ] La clave del repositorio **no** es la contraseña del bucket.
- [ ] Cada cliente tiene su propio usuario, no se comparte.
- [ ] `kopia server user list` no muestra usuarios que no reconocés.
- [ ] Los clientes usan `--override-hostname` y `--override-username`.
- [ ] Evaluaste activar ACL si el servidor atiende más de un cliente.
- [ ] Las claves del bucket son claves de aplicación dedicadas, no la raíz.

## Fuentes

- Repository Server y ACL: <https://kopia.io/docs/repository-server/>
- FAQ (cifrado y contraseña): <https://kopia.io/docs/faqs/>
- Banderas: `cli/command_server.go`,
  `cli/command_server_start.go`,
  <https://github.com/kopia/kopia/tree/master/cli>
- Autenticación del servidor: `cli/command_server_start.go`, función
  `getAuthenticator`