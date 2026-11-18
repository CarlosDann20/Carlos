# Limitaciones conocidas

Documentadas con honestidad, como se pidió: ninguna de estas partes se presenta
como funcional si no lo está.

## 1. Compilación y firma (entorno de desarrollo)
El proyecto se construyó en **Linux**, sin Xcode/Swift/SDK de iPadOS y sin poder
instalarlos. Por tanto **no se generó** el binario ni el **`.ipa` firmado**. El
proyecto está **listo para compilar** en un Mac; los pasos y los requisitos de
firma que faltan están en [`INSTALACION_Y_FIRMA.md`](INSTALACION_Y_FIRMA.md). No
se ejecutó la suite XCTest aquí (sí la validación Python equivalente del núcleo).

## 2. Importación del formato Anki **v3** (zstd) — la limitación más relevante
Memora importa **completamente** los paquetes heredados (Legacy1/Legacy2, que es
lo que produce Anki al marcar **«Admitir versiones anteriores de Anki»** al
exportar). El **formato v3** (`collection.anki21b`, comprimido con **zstd**,
esquema 18 con tablas y configuraciones en **protobuf**, e índice de medios
también protobuf) **se detecta pero no se importa todavía**: la app muestra un
aviso claro pidiendo reexportar en formato heredado (un solo clic en Anki). Se
decidió así para **no depender** de bibliotecas nativas (zstd/protobuf) y mantener
el 100 % offline, y para **no entregar un importador v3 a medias**. El punto de
extensión está preparado en `AnkiPackage`.

- *Solución para el usuario:* en Anki, **Archivo → Exportar → Paquete de Anki
  (.apkg)** y marcar **«Admitir versiones anteriores de Anki»**. El `.apkg`
  resultante se importa al 100 %.

## 3. Exportación `.apkg`
Se exporta en **formato heredado** (`collection.anki2`, legible por Anki). La
exportación es **best‑effort**: dado que en este entorno **no hay Anki** para
verificar la importación, conviene **comprobar el `.apkg` exportado en Anki real**
antes de confiar en él para migraciones críticas. Detalles conocidos:
- Los campos JSON de modelos/mazos se rellenan con valores por defecto
  razonables; el array `req` de los modelos se genera de forma simplificada
  (Anki moderno lo recalcula).
- Intervalos de graduación/fácil en SM‑2 fijados a los valores por defecto de
  Anki (1 y 4 días).
- El escritor ZIP de exportación es ZIP estándar (no ZIP64); colecciones con más
  de 65.535 entradas de medios podrían necesitar dividir la exportación.

## 4. Programación: paridad con Anki
FSRS‑6 y SM‑2 son **reales** y FSRS está validado 1:1 con py‑fsrs. El
**enterrado de hermanas** (bury siblings) está implementado: al responder una
tarjeta se posponen sus hermanas según la configuración del mazo, y se reponen al
iniciar una nueva sesión de ese mazo (en lugar de exactamente al corte diario
como en Anki; es una aproximación simple y segura). Aun así, Memora **no replica
bit a bit toda la cola de Anki** (orden exacto de intercalado, estudio filtrado
avanzado). Al importar desde Anki se conserva el estado por tarjeta
(incluido FSRS `s`/`d`); los **parámetros FSRS** del mazo se ponen a los valores
por defecto (no se leen del paquete), así que, si venías optimizando parámetros en
Anki, conviene **reoptimizar** o ajustarlos. El `left` de aprendizaje de Anki se
mapea de forma aproximada (paso 0).

## 5. Funciones de plantilla no soportadas
`{{type:…}}` (respuesta escrita), TTS (`{{tts:…}}`), LaTeX/MathJax y add‑ons con
JavaScript propio **no** se interpretan de forma especial: se muestra el contenido
del campo y **se avisa**. El HTML/CSS estándar sí se respeta.

## 6. Estudio filtrado / personalizado
Existe el estudio «de todos modos» (ignorar límites del día) y las bases para
mazos filtrados (`odue`/`odid`), pero **no** hay todavía un constructor completo
de mazos dinámicos con consultas tipo Anki.

## 7. Estadísticas
Varias métricas (historial, previsión, actividad) son de **toda la colección**;
el desglose por estado sí puede acotarse a un mazo. No hay aún un “tiempo por
tarjeta” histórico detallado más allá del `revlog`.

## 8. Sincronización
Inexistente **por diseño** (requisito del proyecto): Memora es exclusivamente
local. El traslado entre dispositivos se hace con **copias de seguridad** o
**exportación `.apkg`**.
