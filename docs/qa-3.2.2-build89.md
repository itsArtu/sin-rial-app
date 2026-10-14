# Sin Rial 3.2.2 - Build 89

Publicacion aprobada por el usuario el 14 de octubre de 2026.
Tag: v3.2.2+89. Incluye los cambios probados en builds 85 a 88.
Notas para usuarios: release/3.2.2.md.

## Validacion final

- Flutter: 412 pruebas aprobadas, 1 benchmark optativo omitido.
- Actualizador: tag 3.2.2+89, rechazo de versiones propias/anteriores y
  reconocimiento de una version futura; recorrido ligado a 3.2.2+89.
- Android/JVM de la app: 125 pruebas, 0 fallos, errores u omisiones.
  Tarea :app:testDebugUnitTest aprobada.
- La tarea global testDebugUnitTest tambien ejecuto pruebas de local_auth_android:
  sus 2 clases no pudieron inicializar porque su entorno de Robolectric admite
  SDK hasta 35 y el proyecto tiene targetSdk 36. Esto no afecta los resultados
  de las 125 pruebas propias. No se cambiaron dependencias para esta publicacion.
- Analisis estatico: 0 errores, 0 advertencias y 430 avisos informativos.
- git diff --check aprobado.
- 235 archivos de produccion/pruebas/assets/configuracion comparados con staging,
  sin diferencias antes de compilar.
- La revision visual y la instalacion conservando datos se realizaron en build 88;
  esta version solo cambia numeracion y metadatos de publicacion.
- No se instalo build 89 en el telefono: queda build 88 para probar el actualizador.

## APK

- Archivo: release/sin-rial-3.2.2-build89.apk.
- Tamano: 66014419 bytes.
- SHA-256: 1c798758538d6a63d521d5845ed34b77b595485a692a47680da863366b7f4838.
- versionName 3.2.2; versionCode 89; minSdk 24; targetSdk 36.
- ARM32, ARM64 y x86_64; release no depurable; alineacion ZIP 16 KiB aprobada.
- Firma v2 con el certificado historico:
  6e0965ff509debd2db0a5b628f6d55441457cf2fff320b44e70d2d33e62aa2a3.
  Se conserva la firma para actualizar sin desinstalar.
- Compilacion: flutter build apk --release --build-name=3.2.2 --build-number=89.

## Evidencia y publicacion

Logs en build del staging: test-build89.log, native-test-build89.log,
native-app-test-build89.log, analyze-build89.log y apk-build89.log.
Evidencia visual y de instalacion anterior: docs/qa-3.2.1-build88.md.

Procedimiento: commit selectivo y tag, release en borrador con APK/checksum/manifest,
verificacion de tamanos y digests en GitHub, publicacion como estable/latest,
descarga publica de la APK y comparacion SHA-256. Se excluyen archivos previos
no relacionados, como docs/performance-20260916.md.
