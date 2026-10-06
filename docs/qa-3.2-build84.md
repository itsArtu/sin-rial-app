# Sin Rial 3.2 - build 84

Publicacion aprobada por el usuario el 6 de octubre de 2026.
Tag previsto: v3.2+84.

## Recorridos

- Nuevos usuarios: configuracion inicial, recorrido general y despues inicio.
- Actualizaciones: solo novedades de 3.2; no repite la configuracion inicial.
- Omitir y completar se conservan al reiniciar. Un recorrido pendiente sigue
  disponible tras reiniciar. No se muestran dos recorridos consecutivos.
- El PIN, si esta activado, protege ambos recorridos.
- Crear la primera cuenta espera a completar u omitir el recorrido.
- La salida respeta la preferencia de movimiento reducido del sistema.

## Verificacion

- Flutter: 361 pruebas aprobadas; un benchmark opt-in omitido.
- Android/JVM: 119 pruebas, cero errores, fallos u omisiones.
- Analizador: cero errores y advertencias; 452 avisos informativos.
- Cuatro pruebas visuales adicionales de configuracion y recorrido, a 320/390
  de ancho en claro/oscuro. Veinte capturas de las cinco paginas del recorrido;
  inspeccion del titulo largo en oscuro y de la ultima pagina en claro a 320.
- APK release: versionName 3.2, versionCode 84, no debuggable, minSdk 24,
  targetSdk 36 y bibliotecas ARM32/64 y x86_64.
- Firma v2 verificada y alineacion 16 KiB correcta. Se conserva el certificado
  existente para permitir actualizaciones. Su nombre historico es Android Debug.
- Actualizacion desde build 83 con adb install -r en emulador Android 15,
  sin desinstalar ni borrar datos. PIN existente, perfil y saldo conservados.
- Inicio accesible tras desbloquear. El recorrido ya omitido no reaparece.
  Sin errores en los buffers de crash ni AndroidRuntime/Flutter al arrancar.
- El telefono no estaba conectado por ADB durante esta comprobacion final.
  Build 84 no se ha instalado en el telefono desde esta sesion.

## Artefacto

- release/sin-rial-3.2-build84.apk
- 65,862,858 bytes
- SHA-256: 181D16FA2A0293B7C5B1EDE64DE6321376830D086028D94D95356A1E11D39190
- Certificado SHA-256: 6e0965ff509debd2db0a5b628f6d55441457cf2fff320b44e70d2d33e62aa2a3

El pubspec conserva la forma semver 3.2.0+84; la compilacion usa
flutter build apk --release --build-name=3.2 --build-number=84.
Las pruebas y la compilacion se ejecutaron secuencialmente fuera de OneDrive.
Los fuentes de produccion coinciden con el staging; solo el registrante de
plugins generado difiere despues de quitar integration_test de la APK release.

La publicacion se realiza primero como borrador, comprobando tamanos y hashes
de sus assets antes de publicarla y descargando la APK publica para comparar
su SHA-256 con el artefacto verificado localmente.
