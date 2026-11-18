# Arquitectura de Memora

## Visión general

Memora separa un **núcleo (`Core`) independiente de la interfaz** —datos,
importador, programadores, exportación— de una **capa de presentación SwiftUI
(`Features` + `App`)**. El núcleo no importa SwiftUI (salvo tipos triviales) y es
determinista y testeable; la interfaz es delgada y observa al núcleo.

```
┌───────────────────────────────── App (SwiftUI, @MainActor) ─────────────────────────────┐
│  MemoraApp → RootView → (Decks | Study | Browser | Stats | Settings)                     │
│  AppEnvironment: abre el store, ejecuta import/export/backup en segundo plano, refresca  │
└───────────────┬──────────────────────────────────────────────────────────────────────────┘
                │ llamadas síncronas (lecturas) / en cola de trabajo (operaciones pesadas)
┌───────────────▼──────────────────────────── Core ────────────────────────────────────────┐
│  MemoraStore  ── SQLite (esquema + índices) ── Decks/Notes/Cards/Notetypes/Media/Revlog   │
│  AnkiImporter ── AnkiPackage (ZIP, versión) ── AnkiCollectionReader (schema 11)           │
│  ReviewScheduler ── FSRSScheduler (FSRS‑6) / SM2Scheduler                                  │
│  CardRenderer ── TemplateRenderer + ClozeRenderer                                         │
│  AnkiExporter / BackupManager ── ZipWriter / ZipReader / Deflate (Compression)            │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

## Decisiones técnicas

### SQLite crudo en lugar de SwiftData / Core Data
El objetivo son **4.000–50.000+ tarjetas** con consultas de programación tipo
Anki (`deck_id, state, due`). SQLite con índices a medida y sentencias preparadas
ofrece rendimiento predecible y control total del esquema; SwiftData añade una
capa opaca y menos predecible a esa escala. El importador también lee y escribe
SQLite, así que el modelo encaja de forma natural. El acceso se encapsula en
`SQLiteDatabase` (apertura con WAL, `busy_timeout`, transacciones **reentrantes**
vía `SAVEPOINT`, copia de seguridad con la API online de SQLite, `integrity_check`).

### Esquema (resumen)
`collection` (ajustes) · `deck_config` (JSON) · `decks` · `notetypes` + `fields`
+ `templates` · `notes` (con `sfld`, `csum`, `search_text`) · `cards` · `revlog`
· `media` · `tags`. Índices clave: `cards(deck_id,state,due)` para construir la
cola de estudio, `cards(note_id)`, `notes(csum)` para duplicados, `notes(guid)`.

### Programadores (lógica pura y testeable)
- **FSRS‑6** (`FSRSScheduler`): port fiel de la referencia `py‑fsrs` (21
  parámetros, *decay* aprendible, estabilidad/dificultad, retención deseada,
  pasos de aprendizaje/reaprendizaje, *fuzz*). Se validó numéricamente 1:1 con
  py‑fsrs (ver `docs/PRUEBAS.md`).
- **SM‑2** (`SM2Scheduler`): fórmula canónica de factor de facilidad
  `EF' = EF + (0.1 − (5−q)(0.08 + (5−q)·0.02))`, con pasos y modificadores
  estilo Anki.
- `ReviewScheduler` aplica un programador a una `Card`, calcula el próximo
  vencimiento (sub‑día en segundos o días con alineación al corte diario con
  `DayClock`), escribe el `ReviewLog` y gestiona *leeches*. Es puro: no toca la
  base de datos; el `MemoraStore.commit` persiste el resultado en una transacción.

### Importador `.apkg`
`AnkiPackage` abre el ZIP y determina la versión siguiendo la lógica del código
fuente de Anki (`rslib/.../package/meta.rs`): si hay archivo `meta` (protobuf
`PackageMetadata`), su campo 1 es la versión (1/2 heredadas, 3 = v3/zstd); si no,
se deduce por la presencia de `collection.anki21`/`collection.anki2`.
`AnkiCollectionReader` lee el esquema 11 (JSON de `col.models`/`col.decks`/
`col.dconf`, y filas de `notes`/`cards`/`revlog`) en *streaming*. `AnkiImporter`
mapea todo a Memora **en una sola transacción** (atómico), con **deduplicación**
por `guid` y por tipo+primer campo, mapeo de ids, conversión de programación y
conservación de `stability`/`difficulty` del `cards.data` cuando el paquete usa
FSRS. Los medios se escriben después (aditivo, con nombres saneados).

### ZIP nativo sin dependencias
`ZipReader`/`ZipWriter` implementan STORE y DEFLATE sobre el framework
**Compression** de Apple (`COMPRESSION_ZLIB` = DEFLATE crudo, exactamente el
método 8 de ZIP). El lector soporta **ZIP64** (colecciones con muchos medios) y
aplica **protección anti *zip‑slip*** (saneado de rutas) y **anti bomba**
(límites de tamaño por entrada y totales). Así se evita cualquier dependencia de
terceros y se cumple el requisito de funcionamiento offline.

### Render de tarjetas
`CardRenderer` compone la pregunta y la respuesta a partir de la nota y su tipo;
`TemplateRenderer` resuelve campos `{{Campo}}`, `{{FrontSide}}`, condicionales
`{{#Campo}}`/`{{^Campo}}` y filtros `text:`, `hint:`, `cloze:`. Un filtro no
soportado **no pierde contenido**: muestra el campo y **registra un aviso** que la
interfaz enseña. `ClozeRenderer` implementa `{{cN::texto::pista}}`. El HTML se
muestra en un `WKWebView` con `baseURL` = carpeta de medios (los `src` y los
`[sound:…]`→`<audio>` resuelven a archivos locales) y una **regla de contenido
que bloquea cargas http/https** para garantizar el modo offline.

### Concurrencia
Las lecturas (rápidas) se hacen en el hilo principal. Las operaciones pesadas
(importar, exportar, copia, restaurar) corren en una **cola serie** mostrando un
overlay modal que impide interacción concurrente; así el `transactionDepth` del
store nunca se toca desde dos hilos a la vez. SQLite se abre con `FULLMUTEX`.

### Persistencia e integridad
Todo vive bajo *Application Support/Memora* (`collection.sqlite` + `media/`).
WAL permite recuperación tras cierres inesperados. Las importaciones son
transaccionales (rollback ante error). Las copias de seguridad validan la
integridad de la base **antes** de restaurar, de modo que una copia dañada nunca
destruye la colección existente.
