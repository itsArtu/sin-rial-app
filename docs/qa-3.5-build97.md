# Sin Rial 3.5.0 - Build 97

Fecha: 2026-10-22. Version tecnica: 3.5.0+97. Verificacion previa a la publicacion; la validacion inicial se hizo como entrega local.

## Alcance

- El formulario y el teclado comparten la altura real disponible. Primero se mide el contenido y luego se asigna la altura del teclado, manteniendo botones de al menos 44 px y un maximo de 72 px.
- En pantallas altas crecen el monto, el selector de cuenta, sus logos, la descripcion y los controles. En pantallas compactas se conserva una presentacion reducida.
- Fecha y hora ocupan el ancho de la fila cuando no hay mas opciones. Teclas con radio proporcional a su altura.
- El teclado permanece anclado abajo; no cambia de posicion al introducir montos largos ni al desplazar campos adicionales. Su altura puede cambiar al seleccionar otro tipo de movimiento, segun la cantidad de contenido.
- La tasa de transferencia tiene una linea reservada para evitar saltos al calcularla o al mostrar importes largos.
- Los campos monetarios tienen altura estable; cursor y simbolo quedan contenidos. El boton de volver, que solo contiene un icono, no escala con la fuente del sistema.
- Los detalles permanecen visibles. Se conserva scroll de respaldo para accesibilidad, orientacion horizontal, teclado nativo y campos adicionales de deudas o comisiones.
- Sin modificaciones en operaciones financieras, persistencia, firma configurada ni novedades de actualizacion. El identificador del build permite mostrar las novedades una vez al actualizar.

## Verificacion

- 488 pruebas Flutter aprobadas; 1 benchmark opcional omitido.
- 41 pruebas visuales/de interaccion aprobadas con fuentes reales. Las 10 pruebas adaptables se repitieron despues de reforzar la comprobacion de desplazamiento con texto ampliado.
- 98 capturas en build/release97-qa. Formulario principal comprobado en 320x640, 360x780, 390x844 y 412x915, USD/VES, ingreso/gasto/transferencia y areas seguras de 24 px arriba y abajo.
- Casos adicionales: texto al 150%, giro a 844x390, teclado nativo, montos largos, retorno a vertical y conservacion de nota/monto.
- 127 pruebas Android/JVM en 12 suites: 0 fallos, 0 errores, 0 omisiones.
- Analizador: 0 errores, 0 advertencias, 444 avisos informativos existentes de convenciones y APIs.
- 253 archivos de codigo, pruebas, recursos y configuracion identicos entre repo y staging, excluyendo el registro de plugins generado por Flutter.
- git diff --check aprobado. ADB sin dispositivos conectados.

## Evidencia

Staging: C:/Users/Arturo/AppData/Local/SinRialBuilds/finance-final-20260916-124535.

- build/test-build97-final.log
- build/targeted-build97-final.log
- build/visual-build97-final.log
- build/visual-build97-adaptive.log
- build/analyze-build97-final.log
- android/native-build97.log
- build/apk-build97.log
- build/release97-qa

## Limites

- La ausencia de scroll se verifica para los flujos principales y tamanos indicados, no para cualquier combinacion de accesibilidad o campos adicionales.
- No se instalo el APK ni se midieron FPS en un telefono fisico.
- La validacion inicial no publico en GitHub ni modifico release/latest.json.

## APK verificado

- Archivo: release/sin-rial-3.5-prueba-build97.apk. 69734623 bytes.
- Paquete com.lacaprichosa.app, nombre Sin Rial, versionName 3.5.0, versionCode 97.
- No depurable, minSdk 24, targetSdk 36, ARM32/ARM64/x86_64.
- SHA-256: 447c81da19eceff5659e3f5ba99487263ef3ac79f4672dc6c535210329228a92. La copia entregada coincide con el artefacto de staging.
- Firma v2 y alineacion de 16 KiB verificadas.
- Certificado SHA-256: 6e0965ff509debd2db0a5b628f6d55441457cf2fff320b44e70d2d33e62aa2a3. Coincide con el build 96; se mantiene la identidad existente con DN Android Debug para permitir la actualizacion.
- Sin clase IntegrationTestPlugin en DEX ni registro de plugins de release.
- Durante la validacion inicial, release/latest.json conservaba SHA-256 88f446a5b3c53d0917a450bda0366ab803e14fc1f3f65906610f3d63d0b53bf.

## Preparacion de la publicacion

- Publicacion autorizada por el usuario el 2026-10-22, con tag v3.5.0+97.
- El APK de prueba se promueve como release/sin-rial-3.5.0-build97.apk sin recompilar ni modificar sus bytes; mismo tamano y SHA-256.
- Firma v2, metadatos y alineacion de 16 KiB verificados nuevamente. El certificado coincide tambien con el APK publico 3.2.2+89, cuyo SHA-256 local coincide con el digest publicado en GitHub.
- Codigo, recursos, pruebas y configuracion de la entrega coinciden con el staging probado. No se incluyen cambios generados de Windows ni documentos ajenos a esta publicacion.
- release/latest.json y el checksum publico identifican la version 3.5.0, build 97 y el APK verificado.
- La publicacion se prepara primero como borrador; antes de marcarla estable se contrastan los tres adjuntos (APK, checksum y manifiesto). La comprobacion final incluye descargar el APK y el manifiesto desde sus URLs publicas.
