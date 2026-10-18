# LICENCIAS.md — Hefesto Studio, kit de respaldo Kopia

Este kit combina software con licencias distintas. Las obligaciones son
**distintas** y conviene conocerlas antes de revenderlo.

---

## 1. Kopia — Apache License 2.0

| Dato | Valor |
|---|---|
| Componente | Kopia (binario y servidor) |
| Licencia | **Apache-2.0** (`spdx_id: Apache-2.0`) |
| Fuente | <https://github.com/kopia/kopia> |
| Sitio oficial | <https://kopia.io> |
| Texto de la licencia | <https://www.apache.org/licenses/LICENSE-2.0> |

Verificación: API de GitHub, campo `license.spdx_id` del repositorio `kopia/kopia`.

### Qué significa para Hefesto

**Se puede vender.** Apache-2.0 es una licencia permisiva: permite uso comercial,
modificación y redistribución.

### Qué obligaciones tiene

1. **Atribución.** Hay que indicar que Kopia es obra de sus autores y usar la
   licencia Apache-2.0.
2. **Aviso de patentes y marcas.** Si hay Patents Notice o trademarks en el
   código, hay que respetarlo tal cual.
3. **Estado de modificaciones.** Si se modifica el código, hay que destacar los
   cambios. **Este kit no modifica el código de Kopia**: usa la imagen oficial
   sin tocar una línea. Este punto no aplica hoy, pero aplica si alguien
   parchea algo.
4. **Sin garantía.** Apache-2.0 es "AS IS", sin garantía de ningún tipo.
   Ver `docs/08-SERVICIOS-COMERCIALES.md`: eso no impide vender un servicio
   gestionado, pero obliga a ser claro sobre qué se promete.

### Copyleft

**Apache-2.0 no es copyleft.** No hay obligación de publicar el código propio
que se integre con Kopia. Los scripts de este kit (`scripts/`) pueden quedar
propietarios de Hefesto.

---

## 2. Imagen Docker `kopia/kopia`

| Dato | Valor |
|---|---|
| Componente | Imagen oficial publicada por el proyecto |
| Licencia | **Apache-2.0** (mismo proyecto) |
| Registro | Docker Hub, organización `kopia` |
| Repositorio | <https://github.com/kopia/kopia/tree/master/tools/docker> |

La imagen no agrega licencia nueva: empaqueta el binario de Kopia más
`rclone` (Apache-2.0 / MIT en parte) y paquetes del sistema.

---

## 3. Dependencias dentro de la imagen

La imagen oficial parte de `ubuntu:jammy` e instala paquetes de Ubuntu
(fuse3, curl, tzdata, sshfs, ca-certificates) más `rclone`.

- **Paquetes de Ubuntu:** cada uno con su propia licencia, mayormente libres.
  Se enumeran en el `Dockerfile` oficial.
- **rclone:** <https://rclone.org/> — mayormente MIT y GPL-3.0 según el
  componente. Va copiado, no vinculado: no impone copyleft sobre este kit.
- **Go y sus librerías:** Kopia está escrito en Go. La licencia depende de cada
  dependencia, todas libres en la práctica.

> **Nota de honestidad:** no auditamos componente por componente la cadena de
> licencias del árbol de dependencias de Kopia. La responsabilidad asumida es
> que el proyecto completo se distribuye bajo Apache-2.0. Para una auditoría de
> nivel corporativo, hay que revisar `go.mod` del proyecto.

---

## 4. Software propio de Hefesto

| Archivo | Licencia | Autor |
|---|---|---|
| `scripts/lib.sh` | Propiedad de Hefesto Studio | Hefesto Studio |
| `scripts/crear-repositorio.sh` | Propiedad de Hefesto Studio | Hefesto Studio |
| `scripts/respaldar.sh` | Propiedad de Hefesto Studio | Hefesto Studio |
| `scripts/verificar.sh` | Propiedad de Hefesto Studio | Hefesto Studio |
| `scripts/restaurar.sh` | Propiedad de Hefesto Studio | Hefesto Studio |
| `compose.yaml`, `compose.tls.yaml` | Propiedad de Hefesto Studio | Hefesto Studio |
| `docs/`, `README.md` y este archivo | Propiedad de Hefesto Studio | Hefesto Studio |

Estos archivos **no** son copyleft: se pueden entregar bajo la licencia que
Hefesto defina.

---

## 5. Atribución que debe acompañar la entrega

Si entregás el kit o el servicio a un cliente, la atribución mínima es:

```
Respaldo gestionado con Kopia (https://kopia.io)
Kopia está bajo licencia Apache License 2.0.
Copyright (c) los autores de Kopia.

Operación y gestión de respaldos: Hefesto Studio.
```

---

## 6. Lo que este kit no incluye

- **Ninguna base de datos.** Kopia no usa motor relacional. Supabase no aplica
  y no se menciona como opción en ningún archivo de este kit.
- **Ninguna aplicación.** Todo lo que corre es el software de Kopia.
- **Ninguna receta de base de datos.** Volcados (`pg_dump`, `mysqldump`) quedan
  fuera del alcance: este kit respalda archivos.

---

## 7. Verificación de la información de este documento

| Dato | Cómo se verificó |
|---|---|
| `Apache-2.0` | `api.github.com/repos/kopia/kopia` → `license.spdx_id` |
| Versión v0.23.1 | `api.github.com/repos/kopia/kopia/releases/latest` |
| Digest de la imagen | API de Docker Hub, tag `0.23.1` |
| Dockerfile y entrypoint | `tools/docker/Dockerfile` en el repositorio |

Fecha de verificación y comandos exactos: `VERSION.md`.

El texto completo de Apache-2.0 está en
<https://www.apache.org/licenses/LICENSE-2.0> (la imagen oficial también lo
incluye en `/licenses` o similar según la distribución; verificar).