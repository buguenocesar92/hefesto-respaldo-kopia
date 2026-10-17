# config/ — Hefesto Studio, kit de respaldo Kopia

Este directorio guarda la configuración que el operador tiene que mantener a
mano. No hay secretos versionados acá.

## Contenido

| Ruta | Qué es | ¿Se versiona? |
|---|---|---|
| `tls/` | Certificados TLS del servidor de repositorios | **NO.** Está en `.gitignore`. |

## Certificados TLS

Solo hacen falta si exponés el servidor fuera del host propio, es decir si
usás `compose.tls.yaml`. Ver `docs/02-INSTALACION-COOLIFY.md`.

Kopia espera los archivos en:

- `/app/config/tls/kopia.crt`
- `/app/config/tls/kopia.key`

que en el host corresponden a `./config/tls/kopia.crt` y
`./config/tls/kopia.key`.

### Opción A — certificado de una CA (Let's Encrypt, por ejemplo)

Copiá el `fullchain.pem` como `kopia.crt` y la clave privada como `kopia.key`.

### Opción B — certificado autogenerado por Kopia

Kopia puede generar el certificado en el primer arranque:

```yaml
command:
  - server
  - start
  - --address=0.0.0.0:51515
  - --tls-generate-cert
  - --tls-cert-file=/app/config/tls/kopia.crt
  - --tls-key-file=/app/config/tls/kopia.key
```

En el primer arranque imprime la huella:

```
SERVER CERT SHA256: 48537cce585fed39fb26c639eb8ef38143592ba4b4e7677a84a31916398d40f7
```

**Copiá esa huella a `KOPIA_TLS_FINGERPRINT` en el `.env`.** Es pública, no es
un secreto: justamente por eso upstream la imprime en pantalla. Los clientes la
usan con `--server-cert-fingerprint` para verificar el servidor sin depender de
una CA.

Dos advertencias de upstream:

1. Hay que **quitar `--tls-generate-cert` después del primer arranque**. Si lo
   dejás, el servidor falla al reiniciar.
2. El certificado por defecto se emite para `127.0.0.1` y dura 3650 días. Si
   lo vas a usar desde otros nombres, generá el tuyo con los nombres correctos.

Fuente: <https://kopia.io/docs/repository-server/#auto-generated-tls-certificate>

## Permisos

Los certificados y las claves privadas deberían quedar en `600`, y el directorio
en `700`, con el usuario que corre Docker como dueño.