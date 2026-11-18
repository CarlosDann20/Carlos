# Funcionalidades implementadas

## Importación / compatibilidad Anki
- Lectura de `.apkg` **heredado** (Legacy1 `collection.anki2` y Legacy2
  `collection.anki21`, esquema 11), con descompresión ZIP nativa (STORE +
  DEFLATE, ZIP64).
- **Detección de versión** por el protobuf `meta`, siguiendo el código fuente de
  Anki. El formato **v3 (zstd)** se detecta y se informa con guía precisa.
- Lectura de **modelos (tipos de nota)**, **mazos y submazos** (`::`),
  **etiquetas**, **plantillas** (qfmt/afmt), **CSS**, y **opciones de mazo**
  (`dconf`).
- **Medios**: imágenes y audio se extraen y se guardan con su nombre original;
  siguen funcionando tras importar.
- Conservación de **identificadores** cuando no hay colisión, del **historial**
  (`revlog`) y de la **programación** (type/queue/due/ivl/factor/reps/lapses) y
  del **estado FSRS** (`stability`/`difficulty`) del paquete.
- **Deduplicación** por `guid` y por tipo de nota + primer campo; se pueden
  importar varios paquetes **sin sobrescribir** los mazos existentes (fusiona por
  nombre).
- Importación **transaccional y no destructiva**, con **progreso** y **resumen**
  (notas, tarjetas, duplicadas, medios, avisos). Caracteres en español / tildes /
  símbolos conservados (UTF‑8).
- **Saneado de rutas** y **límites de tamaño** frente a `.apkg` maliciosos.

## Tipos de tarjeta y render
- Básica, básica invertida, básica con tarjeta opcional, **Cloze**, varios
  campos, con **imágenes**, con **audio**, y con **HTML/CSS** personalizado.
- Render de plantillas Anki: campos, `{{FrontSide}}`, condicionales
  `{{#…}}`/`{{^…}}`, filtros `text:`, `hint:`, `cloze:`. Un filtro no soportado
  **avisa** y muestra el campo (nunca tarjeta vacía ni pérdida silenciosa).
- `WebView` offline con el CSS original; `[sound:…]` se convierte en reproductor.

## Estudio y repetición espaciada
- Una tarjeta a la vez: pregunta → **mostrar respuesta** → **Again/Hard/Good/Easy**.
- **Intervalos estimados** en cada botón antes de responder.
- Cola dinámica: aprendizaje vencido ahora, luego mezcla de repasos y nuevas
  respetando los **límites diarios**.
- **FSRS‑6** (por defecto) y **SM‑2** (alternativa), reales.
- **Deshacer** la última respuesta; progreso de la sesión; atajos de teclado
  (espacio, 1‑4, z).
- **Estudiar de todos modos / adelantar**: cuando no hay nada vencido, permite
  introducir nuevas por encima del límite y repasar tarjetas que vencen en los
  próximos días.
- **Posponer hermanas** (bury siblings) configurable; detección de *leeches*;
  respeta tarjetas suspendidas.

## Administración de mazos y tarjetas
- Pantalla principal con mazos/submazos, contadores de **nuevas/pendientes/
  repaso**, total por mazo y **próxima revisión**.
- Crear, eliminar, **renombrar**, crear submazos, **mover tarjetas**, importar,
  plegar/desplegar.
- **Navegador**: búsqueda por texto, filtro por etiqueta/favoritas/suspendidas,
  orden por varios criterios, paginado; ver/editar/eliminar/añadir, **favorita**,
  **suspender**, total de tarjetas. Edición regenera tarjetas nuevas sin alterar
  la programación existente.

## Configuración por mazo (sección 6)
Programador (FSRS/SM‑2), nuevas/día, repasos/día, pasos de aprendizaje y
reaprendizaje, retención deseada (FSRS), intervalo máximo, *fuzz*, parámetros
SM‑2 (facilidad inicial, bonus fácil, modificador de intervalo, intervalo
mínimo), orden de nuevas y de repasos, posponer hermanas, umbral y acción de
*leech*, mostrar intervalos en los botones.

## Estadísticas (sección 7)
Hoy (respuestas, % de aciertos, tiempo, nuevas/repasos/aprendizaje), historial de
repasos (30 días), **previsión de vencimientos**, **distribución** por estado
(nuevas/aprendiendo/jóvenes/maduras/suspendidas), **calendario de actividad** y
totales. Gráficas con Swift Charts. Todo local.

## Exportación y copias de seguridad
- **Exportar a `.apkg`** (formato heredado legible por Anki), por mazo o toda la
  colección, con o sin programación; conserva etiquetas, medios e historial.
- **Copia de seguridad** `.memora` (base + medios + manifiesto) y **restauración
  con validación de integridad previa** (no destructiva).
- Comprobación de integridad de la base.

## Diseño y experiencia
Tema oscuro (fondo negro azulado), tipografía redondeada del sistema, botones
grandes, bordes redondeados, diseño adaptativo iPad con barra lateral + panel,
tamaño de texto de las tarjetas ajustable.

## Privacidad
Sin red, sin cuentas, sin anuncios, sin rastreadores; datos solo en el
dispositivo.
