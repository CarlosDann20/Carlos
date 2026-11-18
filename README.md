# Memora

**Aplicación nativa de flashcards para iPadOS, offline y compatible con Anki.**

Memora es una app de estudio por repetición espaciada escrita en **Swift + SwiftUI**,
diseñada para iPad, que funciona **100 % sin conexión**, sin cuentas, sin servidores
y sin telemetría. Importa paquetes **`.apkg` de Anki**, administra decenas de miles
de tarjetas sobre **SQLite** y programa repasos con **FSRS‑6** (y **SM‑2** como
alternativa).

> Nombre provisional: **Memora** (de *memoria* + *memorar*).

---

## ⚠️ Estado de compilación (lee esto primero — es importante y honesto)

Este proyecto se desarrolló en un contenedor **Linux**, donde **no existen Xcode,
Swift ni el SDK de iPadOS**, y donde el toolchain de Swift no se puede instalar
(el host de descarga está bloqueado por la red). En consecuencia:

- ✅ **El proyecto fuente de Xcode está completo y listo para compilar.**
- ✅ La lógica crítica (algoritmo **FSRS‑6**, **SM‑2** y el **manejo del formato
  `.apkg`**) se **validó de forma ejecutable con Python** contra las
  implementaciones de referencia (ver [`docs/PRUEBAS.md`](docs/PRUEBAS.md)).
- ❌ **No se pudo compilar la app, ni generar un `.app` o un `.ipa` firmado aquí.**
  Eso requiere **macOS + Xcode** y, para instalar en un iPad, **credenciales de
  firma de Apple** (Apple ID gratuito o cuenta de desarrollador).

**No se ha simulado ninguna compilación ni instalación.** Lo que falta para
obtener el `.ipa` instalable y cómo completarlo está detallado en
[`docs/INSTALACION_Y_FIRMA.md`](docs/INSTALACION_Y_FIRMA.md).

---

## Compilar y ejecutar (en un Mac con Xcode 16+)

Tienes tres caminos; el primero es el recomendado.

### Opción A — Abrir el proyecto incluido (Xcode 16 o superior)
```bash
open Memora.xcodeproj
```
Selecciona el esquema **Memora**, un simulador de iPad (o tu iPad) y pulsa **⌘R**.

### Opción B — Regenerar el proyecto con XcodeGen (robusto, cualquier Xcode reciente)
```bash
brew install xcodegen
xcodegen generate
open Memora.xcodeproj
```
`project.yml` es la fuente de verdad de la estructura del proyecto.

### Opción C — Proyecto nuevo a mano
Crea una *App* de iOS en Xcode llamada `Memora`, borra sus archivos de ejemplo y
arrastra la carpeta `Memora/` (y `MemoraTests/` al target de pruebas). No hay
dependencias externas.

### Ejecutar las pruebas
```bash
xcodebuild test -scheme Memora -destination 'platform=iOS Simulator,name=iPad (10th generation)'
```
o **⌘U** en Xcode. Ver [`docs/PRUEBAS.md`](docs/PRUEBAS.md).

**Requisitos:** macOS con **Xcode 16+**, **iPadOS 17+** como destino. Sin
CocoaPods, SPM remoto ni ninguna dependencia de terceros.

### Compilar en la nube sin Mac (GitHub Actions)
No necesitas un Mac para **compilar y probar**: el repositorio incluye un flujo de
**GitHub Actions con runner macOS** (`.github/workflows/ci.yml`) que compila con
Xcode, muestra los errores Swift reales, ejecuta los XCTest y publica artefactos
(logs, `.xcresult`, IPA sin firmar). Para **instalar en el iPad sin Mac** hay un
segundo flujo que sube a **TestFlight** (requiere cuenta Apple de pago).

> ⚠️ **Importante (comprobado en una ejecución real):** los runners **macOS de
> GitHub están restringidos en esta cuenta** (Linux sí funciona). Hay que
> **desbloquearlos añadiendo un método de pago** (en repo público el coste suele
> ser 0 €) **o** usar **Codemagic** (incluido `codemagic.yaml`, máquinas macOS
> propias, plan gratuito). Pasos exactos y el resultado del diagnóstico en
> **[`docs/CI_Y_FIRMA.md`](docs/CI_Y_FIRMA.md)**.

---

## Validación ejecutada en este entorno (Python)

Aunque no hay Swift aquí, sí se validó la lógica más delicada:

```bash
python3 scripts/validate_fsrs.py     # FSRS‑6 vs py‑fsrs (referencia)  -> 54/54 OK
python3 scripts/validate_sm2.py      # SM‑2: fórmula EF y expectativas de las pruebas
python3 scripts/make_apkg.py         # genera fixtures .apkg reales
python3 scripts/validate_import.py   # verifica el manejo del formato .apkg
```
Resultados y metodología en [`docs/PRUEBAS.md`](docs/PRUEBAS.md).

---

## Estructura del proyecto

```
Memora/
  App/            MemoraApp (@main), AppEnvironment (coordinación), RootView
  Core/
    Models/       Deck, Notetype, Note, Card, ReviewLog, DeckConfig, …
    Storage/      SQLite (esquema + índices) y stores por dominio
    Scheduler/    FSRS‑6, SM‑2, ReviewScheduler
    Importer/     .apkg (ZIP, detección de versión, lectura schema 11),
                  render de plantillas y cloze
    Export/       Exportación .apkg, ZipWriter, copias de seguridad
    Support/      SQLite wrapper, DEFLATE, SHA1, CRC32, utilidades
  Features/       SwiftUI: Decks, Study, Browser, Stats, Settings, Shared
  Resources/      Info.plist, Assets.xcassets (icono, color de acento)
MemoraTests/      XCTest + Fixtures/ (.apkg reales)
scripts/          Validadores y generadores (Python)
docs/             Arquitectura, manual, funcionalidades, límites, pruebas, firma
```

## Documentación

| Documento | Contenido |
|---|---|
| [`docs/ARQUITECTURA.md`](docs/ARQUITECTURA.md) | Diseño, módulos, decisiones técnicas |
| [`docs/MANUAL.md`](docs/MANUAL.md) | Manual breve de uso |
| [`docs/FUNCIONALIDADES.md`](docs/FUNCIONALIDADES.md) | Lista de funcionalidades implementadas |
| [`docs/LIMITACIONES.md`](docs/LIMITACIONES.md) | Limitaciones conocidas |
| [`docs/PRUEBAS.md`](docs/PRUEBAS.md) | Pruebas ejecutadas y resultados |
| [`docs/INSTALACION_Y_FIRMA.md`](docs/INSTALACION_Y_FIRMA.md) | Instalar en el iPad y requisitos de firma |
| [`docs/CI_Y_FIRMA.md`](docs/CI_Y_FIRMA.md) | CI en la nube (Actions/macOS), TestFlight e instalación sin Mac |
| [`docs/LICENCIAS.md`](docs/LICENCIAS.md) | Atribuciones y licencias |

## Privacidad

Memora no realiza ninguna petición de red, no incluye analítica ni anuncios, y
guarda **todos** los datos localmente en el dispositivo. El `WebView` que muestra
las tarjetas bloquea activamente cualquier carga remota.
