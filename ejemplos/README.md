# Ejemplos del kit de respaldo Kopia

Todos los archivos de esta carpeta son **plantillas**. Ninguno contiene
secretos reales. Copiá el que necesites, revisalo y recién después adaptalo.

| Archivo | Para qué sirve | Riesgo |
|---|---|---|
| `01-politica-retencion.ejemplo.json` | Exportar e importar la política de retención entre repositorios | Ninguno |
| `02-respaldo-docker-volume.DEMOSTRACION.sh` | Respaldar un volumen Docker con copia coherente | **Solo demostración** |
| `03-usuarios-repositorio-servidor.ejemplo.txt` | Alta de usuarios del Repository Server | Ninguno |

## La etiqueta `DEMOSTRACION` importa

`02-respaldo-docker-volume.DEMOSTRACION.sh` está marcado así a propósito.
Respaldar los archivos de un volumen Docker **no garantiza una copia
coherente** si el servicio está escribiendo mientras se lee. El script
incluye una pausa, pero eso solo sirve si la aplicación tolera quedar detenida.

Para bases de datos, usá el volcado propio de cada motor
(`pg_dump`, `mysqldump`, `mongodump`) y respaldá **el volcado**, no el volumen.
Este kit no incluye recetas de base de datos: Kopia no habla SQL.

Y nada de Supabase ni de ningún motor relacional: Kopia no usa base de datos.
Ver `docs/08-SERVICIOS-COMERCIALES.md`.