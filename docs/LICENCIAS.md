# Licencias y atribuciones

Memora no incluye binarios ni bibliotecas de terceros. Usa únicamente
*frameworks* del sistema de Apple (SwiftUI, WebKit, SQLite3, Compression,
CryptoKit, Charts). Aun así, parte del conocimiento y de la lógica se basa en
proyectos de código abierto que corresponde reconocer.

## FSRS‑6 (algoritmo de repetición espaciada)
El programador por defecto implementa **FSRS** (Free Spaced Repetition
Scheduler). La implementación de Memora (`FSRSScheduler.swift`) es un **port
fiel** de la implementación de referencia **py‑fsrs**:

- Proyecto: *Open Spaced Repetition* — `open-spaced-repetition/py-fsrs`.
- Licencia: **MIT**.
- Autoría del algoritmo FSRS: **Jarrett Ye** y colaboradores de Open Spaced
  Repetition.

Los parámetros por defecto, las fórmulas (estabilidad, dificultad, retención,
intervalos, *fuzz*) y la máquina de estados de pasos de aprendizaje siguen esa
referencia. Se agradece a sus autores.

> Texto de licencia MIT de py‑fsrs (resumen): se permite usar, copiar, modificar
> y distribuir con la nota de copyright y este aviso. El software se ofrece "tal
> cual", sin garantías. Consulta el repositorio original para el texto completo y
> el titular del copyright.

## Formato de paquete de Anki (consulta de especificación)
El manejo de `.apkg`/esquema 11 y la detección de versiones se basó en la
**documentación y el código fuente de Anki** (`ankitects/anki`, licencia
**AGPL‑3.0**), consultados para **entender el formato** (p. ej.
`rslib/src/import_export/package/meta.rs`, `rslib/src/storage/schema11.sql`,
`proto/anki/import_export.proto`). **No se copió código** de Anki en Memora; solo
se implementó la interoperabilidad con su formato de archivo a partir de esa
especificación. Anki es una marca de sus autores.

## zstd (no incluido)
El soporte completo del formato v3 requeriría **zstd** (licencia BSD, Meta).
Memora **no** incluye zstd actualmente (ver `docs/LIMITACIONES.md`); si en el
futuro se añade para importar v3, deberá incorporarse su aviso de licencia BSD.

## Frameworks de Apple
SwiftUI, WebKit, SQLite3, Compression, CryptoKit y Swift Charts se usan bajo los
términos del SDK de Apple.

## Código de Memora
El resto del código de Memora es original de este proyecto. Elige y añade la
licencia que prefieras (p. ej. MIT o la que corresponda a tu uso); si la publicas,
conserva las atribuciones anteriores.
