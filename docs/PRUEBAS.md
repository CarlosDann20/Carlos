# Pruebas y control de calidad

Hay **dos niveles** de pruebas:

1. **Validación ejecutable en este entorno (Python).** Como aquí no hay Swift,
   se validó la lógica más delicada —el algoritmo **FSRS‑6** y el **manejo del
   formato `.apkg`**— contra las implementaciones de referencia. Estas pruebas
   **sí se ejecutaron** y sus resultados están abajo.
2. **Suite XCTest (Swift).** Cubre la aplicación completa y **se ejecuta en un
   Mac** con `⌘U` o `xcodebuild test`. Mapea el checklist de la sección 12 del
   encargo.

---

## 1. Validación ejecutada aquí (Python)

### 1.1 FSRS‑6 vs. referencia `py‑fsrs`
`scripts/validate_fsrs.py` traduce literalmente `FSRSScheduler.outcome(...)` a
Python y lo compara, paso a paso y con *fuzz* desactivado, contra la librería de
referencia **py‑fsrs** sobre varias secuencias de calificaciones y separaciones
temporales. Compara **estado, estabilidad, dificultad e intervalo**.

```
Checks: 44, mismatches: 0
PASS: Swift FSRS-6 port matches py-fsrs reference exactly.
```

> Durante esta validación se detectó y corrigió un error real: una tarjeta nueva
> que permanece en aprendizaje tras la primera respuesta debía pasar a estado
> `learning` (no quedarse como `new`). Corregido en `FSRSScheduler.swift`.

Los **valores dorados** embebidos en `FSRSSchedulerTests.testGoldenSequence`
provienen directamente de py‑fsrs y se comprobó que son **auto‑consistentes** con
el mirror validado.

### 1.2 Formato `.apkg`
`scripts/make_apkg.py` construye *fixtures* `.apkg` **reales** (SQLite esquema 11,
separador de campos `0x1f`, JSON de modelos/mazos, mapa de medios, protobuf
`meta`). `scripts/validate_import.py` reproduce la lógica de parseo del importador
Swift y la comprueba:

```
meta protobuf version parsed as 3 / 1           [ok]
basic.apkg  → legacy2, 2 tipos, 2 mazos, 3 notas, 3 tarjetas, 2 revlog   [ok]
            → mapa de medios {"0":"img.png"}, cloze c1::Madrid, FSRS s=12.34 [ok]
            → campos separados por 0x1f, referencia de medios conservada   [ok]
legacy1.apkg → legacy1, 1 nota / 1 tarjeta       [ok]
large.apkg   → legacy2, 4000 notas / 4000 tarjetas [ok]
v3stub.apkg  → v3 detectado (el importador lo rechaza con guía) [ok]
PASS: 0 failed check(s)
```

---

## 2. Suite XCTest (ejecutar en Mac)

```bash
xcodebuild test -scheme Memora \
  -destination 'platform=iOS Simulator,name=iPad (10th generation)'
```

| # (sección 12) | Requisito | Prueba XCTest |
|---|---|---|
| 1 | Importar `.apkg` básico | `ImporterAndZipTests.testImportBasic` |
| 2 | Importar >4.000 tarjetas | `testImportLargeCollection` |
| 3 | Tarjetas Cloze | `testImportClozePreserved`, `RenderingTests.testCloze…` |
| 4 | Imágenes y audio | `testImportMediaWritten`, `RenderingTests.testSoundConvertedToAudio` |
| 5 | Plantillas HTML/CSS | `RenderingTests.testCardRendererBasic`, `testDocumentWrappsCSSAndBody` |
| 6 | Conservar etiquetas | `testImportBasic` (tags), `ExportRoundTripTests` |
| 7 | Conservar programación | `testSchedulingAndFSRSPreserved`, `testReviewLogImported` |
| 8 | FSRS funciona | `FSRSSchedulerTests.*` (dorados + monotonía + retención) |
| 9 | SM‑2 funciona | `SM2SchedulerTests.*` (fórmula EF, intervalos, lapsos) |
| 10 | Guardado tras cerrar | `StoreTests.testPersistenceAcrossReopen` |
| 11 | Búsqueda y filtrado | `StoreTests.testSearch` |
| 12 | Exportar y reimportar | `ExportRoundTripTests.testExportThenReimport` |
| 13 | Sin conexión | Sin APIs de red en el proyecto; `WebView` bloquea http/https |
| 14 | Rendimiento con colecciones grandes | `testImportLargeCollection` (4.000), índices SQLite |
| — | Deduplicación | `testDedupOnReimport` |
| — | No destructivo ante fallo | `testImportIsNonDestructiveOnFailure` |
| — | Seguridad de rutas de medios | `StoreTests.testMediaPathTraversalNeutralised` |
| — | Copia de seguridad / restauración | `StoreTests.testBackupAndRestore` |
| — | ZIP (lectura real de `.apkg`) | `ImporterAndZipTests.testZipReaderReadsApkg` |

### Nota sobre la ejecución Swift
La suite XCTest **no pudo ejecutarse en este contenedor Linux** (no hay toolchain
de Swift ni Xcode). Está escrita para ejecutarse en un Mac. La lógica de los dos
subsistemas más propensos a error —FSRS y el formato `.apkg`— ya se validó aquí
con Python (sección 1), por lo que la confianza en esa parte es alta aun antes de
compilar.
