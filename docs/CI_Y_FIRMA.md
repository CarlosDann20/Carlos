# CI en la nube, firma e instalación sin Mac propio

Memora incluye dos *workflows* de **GitHub Actions** (runners **macOS**, con Xcode)
para compilar y entregar la app sin que tú tengas un Mac:

| Workflow | Archivo | Qué hace | ¿Necesita Apple? |
|---|---|---|---|
| **CI (build & test)** | `.github/workflows/ci.yml` | Compila con Xcode, **muestra errores Swift reales**, ejecuta los XCTest, publica un reporte y sube artefactos (logs, resultados, IPA sin firmar). | **No.** Gratis. |
| **Deploy to TestFlight** | `.github/workflows/testflight.yml` | Archiva, **firma** y **sube a TestFlight** para instalar en el iPad sin Mac. | Sí (cuenta de pago + secretos). |

---

## 0. Resultado REAL de la primera ejecución (léelo primero)

Configuré el CI, hice *push* y **lo ejecuté de verdad**. Resultado comprobado en
GitHub Actions:

- ✅ **GitHub Actions funciona en tu cuenta** — un job de **Linux** de prueba
  arrancó y terminó **correctamente**.
- ❌ **Los runners de macOS NO se asignan a tu cuenta**: `macos-14` se cancela al
  instante y `macos-13/15/latest` se quedan **encolados sin arrancar nunca**.
  Como el repositorio es **público** (Linux corre gratis), **no es un problema de
  minutos ni de facturación**: es una **restricción de los runners macOS** que
  GitHub aplica a cuentas nuevas sin método de pago verificado.

**Consecuencia honesta:** sin un runner macOS **no pude compilar la app ni
verificar el código Swift en la nube todavía**. No lo simulo. Hay que desbloquear
macOS (Opción 1) o usar un CI con máquinas macOS propias (Opción 2).

### Opción 1 (recomendada, la más simple) — Desbloquear macOS en GitHub
En un repositorio **público**, los minutos de macOS son **gratuitos**, pero GitHub
exige un **método de pago en el archivo** para habilitar los runners macOS (medida
antifraude para cuentas nuevas). Normalmente el coste real es **0 €**.
1. GitHub → tu avatar → **Settings** → **Billing and licensing** → **Payment
   information** → añade una tarjeta.
2. (Recomendado) **Settings → Billing → Spending limit**: déjalo en **$0** para no
   gastar de más; en repo público no consume de ese límite.
3. Verifica tu correo y activa **2FA** si aún no lo has hecho (ayuda al desbloqueo).
4. Vuelve a lanzar el CI: **Actions → CI (build & test) → Run workflow** (o haz un
   push). Para comprobar rápido si ya hay macOS, lanza **Actions → Preflight →
   Run workflow**: el job `macos` debe ponerse **verde**.

Cuando macOS quede habilitado, **todo lo ya configurado funciona sin tocar nada**
(`ci.yml` compila y prueba; `testflight.yml` instala en el iPad).

### Opción 2 (si no quieres poner tarjeta en GitHub) — Codemagic
**Codemagic** (<https://codemagic.io>) tiene **sus propias máquinas macOS** y un
**plan gratuito (~500 min/mes)**; no depende de los runners de GitHub. El repo ya
incluye **`codemagic.yaml`** listo.
1. Entra en codemagic.io e inicia sesión **con GitHub**.
2. *Add application* → elige `CarlosDann20/Carlos`.
3. Detecta `codemagic.yaml`; lanza el workflow **build-test** (compila + prueba,
   sin cuenta Apple). Para instalar en el iPad, configura la clave de App Store
   Connect en Codemagic y usa el workflow **testflight**.

---

## 1. CI gratuito (ya configurado — compila y prueba)

Se ejecuta **automáticamente en cada push** a la rama de desarrollo (y se puede
lanzar a mano desde la pestaña **Actions → CI (build & test) → Run workflow**).

**Dónde ver los resultados:** pestaña **Actions** del repositorio en GitHub.
- La consola del job muestra la compilación en vivo; si hay un **error de
  compilación Swift**, el job se pone en **rojo** y el error aparece en el log.
- El **resumen del job** (Summary) muestra ✅/❌ de compilación y pruebas y la
  lista de errores.
- **Artefactos descargables** (al final de la página del run):
  - `build-logs` — `build.log` y `test.log` completos.
  - `TestResults` — bundle `.xcresult` (ábrelo en Xcode para ver las pruebas).
  - `Memora-unsigned-ipa` — **IPA sin firmar** (para la Opción B de abajo).

> **Minutos:** en un repositorio **público** los runners macOS son **gratis**. En
> uno **privado** consumen los 2.000 min/mes gratuitos (macOS cuenta ×10, ≈200
> min/mes); una ejecución cabe de sobra. Si se agotan, haz el repo público o
> añade un método de pago con límite de gasto.

Este CI es la **prueba real de que el proyecto compila** en Xcode (aquí, en Linux,
no hay compilador Swift). Si algo no compila, se verá aquí y se corrige.

---

## 2. Instalar en el iPad: opciones reales

### Opción A — TestFlight (recomendada si NO tienes ningún ordenador) · de pago
La **única** forma de instalar en el iPad usando solo el iPad (sin Mac ni PC) es
**TestFlight**. Requiere el **Apple Developer Program (99 USD/año)**.

**Pasos (una sola vez):**
1. Inscríbete en el **Apple Developer Program**: <https://developer.apple.com/programs/>
2. En **App Store Connect** → *Users and Access* → *Integrations* (o *Keys*) →
   **App Store Connect API** → genera una clave con rol **App Manager**. Apunta:
   - **Key ID** (p. ej. `ABC123DEFG`)
   - **Issuer ID** (un UUID)
   - descarga el archivo **`AuthKey_XXXXXX.p8`** (solo se descarga una vez).
3. Apunta tu **Team ID** (10 caracteres): App Store Connect → *Membership*, o
   developer.apple.com → *Membership details*.
4. (Opcional) Crea el registro de la app en App Store Connect con el *bundle id*
   `app.memora.Memora` (o el que uses). Con firma automática suele crearse solo.
5. **Codifica la clave `.p8` en base64** (una línea, sin saltos):
   - macOS: `base64 -i AuthKey_XXXXXX.p8 | pbcopy`
   - Linux: `base64 -w0 AuthKey_XXXXXX.p8`
   - Windows (PowerShell): `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXXXX.p8"))`
6. En GitHub → **Settings → Secrets and variables → Actions → New repository
   secret**, crea:
   | Secreto | Valor |
   |---|---|
   | `ASC_KEY_ID` | el Key ID |
   | `ASC_ISSUER_ID` | el Issuer ID |
   | `ASC_PRIVATE_KEY` | el `.p8` **en base64** (paso 5) |
   | `APPLE_TEAM_ID` | tu Team ID |
   | `APP_BUNDLE_ID` *(opcional)* | `app.memora.Memora` |
7. Ejecuta el workflow: **Actions → Deploy to TestFlight → Run workflow**.

**En tu iPad (sin Mac):**
1. Instala la app **TestFlight** desde la App Store.
2. En App Store Connect → tu app → **TestFlight**, añádete como *tester* interno
   (tu propio Apple ID) o crea un enlace público.
3. Abre la invitación en el iPad, pulsa **Instalar** en TestFlight. Ya puedes
   estudiar. (Las versiones de TestFlight caducan a los 90 días; subir una nueva
   build renueva.)

### Opción B — Gratis, pero con un ordenador (Windows o Mac)
Coste **0 €**, sin cuenta de desarrollador de pago, pero necesitas **un ordenador**
(no hace falta que sea Mac):
1. Descarga el artefacto **`Memora-unsigned-ipa`** del último run de CI.
2. En el ordenador instala **AltStore** (<https://altstore.io>) o **Sideloadly**
   (<https://sideloadly.io>).
3. Conecta el iPad, inicia sesión con tu **Apple ID gratuito** y firma/instala el
   IPA con esa herramienta.
4. En el iPad: **Ajustes → General → VPN y gestión de dispositivos** → confía en
   el perfil. Abre Memora.
   > Con Apple ID gratuito la app **caduca a los 7 días** y hay que reinstalarla
   > (AltStore puede renovarla automáticamente si dejas AltServer en el PC).

### Opción C — Solo el iPad, gratis y sin ningún ordenador
**No es posible** con las restricciones actuales de Apple: firmar/instalar un IPA
propio exige o bien TestFlight (Opción A, de pago) o bien una herramienta de
*sideloading* en un ordenador (Opción B). No lo simulo ni prometo lo contrario.

---

## 3. Recomendación para tu caso
- Para **solo comprobar que compila y pasar las pruebas**: no hagas nada, el CI ya
  lo hace gratis en cada push.
- Para **instalar en el iPad sin ordenador**: **Opción A (TestFlight)**, asumiendo
  los 99 USD/año.
- Para **instalar gratis** y tienes acceso a un PC: **Opción B** (AltStore/Sideloadly).

---

## 4. Requisitos de Apple (resumen)

| Necesitas | ¿Para qué? | Coste |
|---|---|---|
| Apple ID | Todo | Gratis |
| Apple Developer Program | TestFlight / firma de distribución (Opción A) | 99 USD/año |
| Team ID | Firma | Incluido en el programa |
| Clave API de App Store Connect (`.p8`) | Firmar y subir desde CI sin contraseña | Gratis (con el programa) |
| Un PC con AltStore/Sideloadly | Opción B (gratis) | Gratis (necesitas el PC) |

---

## 5. Seguridad (sin secretos en el repositorio)
- Los secretos se guardan **cifrados en GitHub** (Settings → Secrets) y se usan
  como `${{ secrets.* }}`. **Nunca** se escriben en el repositorio ni en el código.
- La clave `.p8` se entrega **en base64** como secreto; el workflow la decodifica a
  un archivo temporal, la usa y la **borra al final**.
- GitHub **oculta** los secretos en los logs. Aun así, el workflow no los imprime.
- `.gitignore` excluye `*.p12`, `*.p8`, `*.mobileprovision`, `*.ipa`, etc. para
  evitar subirlos por accidente.
- Da a la clave API el rol mínimo necesario (**App Manager**) y puedes revocarla
  en cualquier momento desde App Store Connect.
