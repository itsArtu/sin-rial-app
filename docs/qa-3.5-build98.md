# Sin Rial 3.5.0 - Build 98

Fecha: 2026-10-22. Correccion de la publicacion para permitir actualizar desde la build de prueba 97 y desde la ultima version publica anterior, 3.2.2+89.

## Alcance

- Version 3.5.0+98 en pubspec y numero de build interno 98.
- APK recompilado en modo release, no renombrado desde la build 97.
- Mismos cambios funcionales y visuales de 3.5; sin cambios en calculos, migraciones o datos guardados.
- Identificador de novedades 3.5.0+98, una vez al actualizar; separado de la bienvenida inicial y protegido por el PIN.
- Changelog reorganizado por novedades, correcciones e instalacion, con enlaces directos a APK y checksum.
- La release y la etiqueta v3.5.0+97 se retiran de GitHub despues de publicar y verificar la build 98. Se conservan los APK locales y el historial del codigo.

## Pruebas

- 492 pruebas Flutter aprobadas; 1 benchmark opcional omitido.
- Prueba del actualizador con versiones instaladas simuladas mediante pubspec: 3.2.2+89 y 3.5.0+97 ofrecen 3.5.0+98; la propia 98 no se ofrece de nuevo.
- 17 pruebas de version, actualizador y novedades repetidas con la configuracion final 3.5.0+98, todas aprobadas.
- Novedades comprobadas desde estados persistidos 3.2.2+89 y 3.5.0+97; no reaparecen al reiniciar despues de omitirlas.
- La comparacion de builds del actualizador coincide con la implementacion de la version publica 3.2.2+89.
- 248 archivos de codigo, pruebas, recursos y configuracion coinciden entre el repositorio y el staging de compilacion; se excluye el registro generado de plugins.
- git diff --check aprobado.
- Sin dispositivo ADB conectado: no se realizo una instalacion fisica sobre versiones anteriores.

## APK

- Comando: flutter build apk --release --build-name=3.5.0 --build-number=98.
- Archivo: release/sin-rial-3.5.0-build98.apk, 69734623 bytes.
- Paquete: com.lacaprichosa.app. Nombre: Sin Rial. versionName: 3.5.0. versionCode: 98.
- minSdk 24, targetSdk 36, ARM32/ARM64/x86_64. No depurable.
- SHA-256: 74820d3badb064b63daa60e42b76913bf3d0946d6da18925f00910b8951e58a7.
- Firma v2 y alineacion de 16 KiB verificadas. Certificado SHA-256: 6e0965ff509debd2db0a5b628f6d55441457cf2fff320b44e70d2d33e62aa2a3, igual al de las builds 89 y 97.
- Sin IntegrationTestPlugin en los archivos DEX de release.

## Evidencia local

Staging: C:/Users/Arturo/AppData/Local/SinRialBuilds/finance-final-20260916-124535.

- build/test-build98.log
- build/upgrade98-from89.log
- build/upgrade98-from97.log
- build/upgrade98-current.log
- build/apk-build98.log

## Publicacion

Tag previsto: v3.5.0+98. Validacion previa de los tres adjuntos en borrador: APK, checksum y latest.json. La comprobacion final requiere descargar el APK publico, comparar SHA-256, comprobar el manifiesto y el endpoint latest, y confirmar la ausencia de la release y etiqueta 97.
