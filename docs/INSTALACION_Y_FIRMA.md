# Instalación en el iPad y requisitos de firma

> **Resumen honesto:** este proyecto se construyó en Linux, donde no es posible
> compilar ni firmar apps de iPadOS. Aquí **no se generó** un `.ipa`. Para
> obtener la app instalable necesitas un **Mac con Xcode** y una **identidad de
> firma de Apple**. Abajo están los pasos exactos y lo que falta.

## Qué falta para el `.ipa` instalable
1. **Un Mac con Xcode 16+** (macOS Sonoma/Sequoia).
2. **Una identidad de firma de Apple:**
   - *Gratis:* un **Apple ID** normal sirve para instalar en **tu propio** iPad
     mediante Xcode (el perfil caduca a los 7 días y hay que reinstalar).
   - *De pago:* el **Apple Developer Program** (99 USD/año) permite perfiles de
     1 año, distribución **Ad Hoc**/**TestFlight**/**App Store** y exportar
     `.ipa` firmados.
3. **Establecer el equipo de firma** en el proyecto: en Xcode, target **Memora →
   Signing & Capabilities → Team**, o en `project.yml`/ajustes del target define
   `DEVELOPMENT_TEAM` con tu *Team ID*. El *bundle id* por defecto es
   `app.memora.Memora`; cámbialo si ya está en uso en tu cuenta.

Sin el paso 2–3 Xcode mostrará *"Signing for 'Memora' requires a development
team"*: ese es exactamente el requisito que no se puede cubrir en este entorno.

## Opción 1 — Instalar en tu iPad desde Xcode (Apple ID gratuito)
1. Abre el proyecto: `open Memora.xcodeproj` (o `xcodegen generate` primero).
2. Conecta el iPad por cable y confía en el ordenador.
3. Selecciona el target **Memora**, pon tu **Team** en *Signing & Capabilities*
   (marca *Automatically manage signing*).
4. Elige tu iPad como destino y pulsa **⌘R**.
5. En el iPad: **Ajustes → General → VPN y gestión de dispositivos** → confía en
   tu perfil de desarrollador. Abre Memora.

## Opción 2 — Generar un `.ipa` (cuenta de desarrollador)
1. En Xcode: **Product → Archive**.
2. En el Organizer: **Distribute App → Ad Hoc** (o Development) → firma → exporta.
3. Obtendrás `Memora.ipa`, instalable con Apple Configurator, Xcode (*Devices &
   Simulators → Install*) o un MDM.

Por línea de comandos (requiere firma configurada):
```bash
xcodebuild -scheme Memora -sdk iphoneos -configuration Release \
  -archivePath build/Memora.xcarchive archive
xcodebuild -exportArchive -archivePath build/Memora.xcarchive \
  -exportPath build/ipa -exportOptionsPlist ExportOptions.plist
```
(`ExportOptions.plist` debe indicar tu `teamID` y método de exportación.)

## Probar sin iPad
Funciona en el **Simulador de iPad** de Xcode sin firma: elige un simulador de
iPad y **⌘R**. Para importar un `.apkg`, arrástralo a la app **Archivos** del
simulador y ábrelo desde Memora.

## Notas
- Destino mínimo: **iPadOS 17**. Si tu Xcode no trae ese SDK, baja
  `IPHONEOS_DEPLOYMENT_TARGET` (en `project.yml` o en los ajustes del target)
  a una versión disponible; el código usa APIs de iOS 16–17.
- No hay dependencias externas que instalar.
