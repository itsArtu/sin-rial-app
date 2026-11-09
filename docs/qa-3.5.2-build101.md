# Sin Rial 3.5.2 - Build 101

Fecha: 2026-11-09. Compilacion y validacion de la version 3.5.2, build 101.

## Cambios

- Deudas: se normalizan residuos binarios cercanos al centavo. Una deuda marcada como pagada conserva su liquidacion si quedo un residuo de hasta un centavo tras la truncacion. Una deuda pendiente de un centavo sigue pendiente. No se crean movimientos ni se modifican los saldos de las cuentas durante la reparacion.
- Criterio consistente en cuotas, abonos, recordatorios, edicion, borrado y deshacer. Se mantiene la presentacion general de dos decimales sin redondear hacia arriba.
- Recordatorios: textos diferenciados para pagos/cobros de hoy, proximos y vencidos; recuperacion de alarmas antiguas no entregadas y proteccion contra avisos duplicados del mismo dia. Se respeta un margen de 15 minutos para no reprogramar innecesariamente una alarma ligeramente retrasada.
- Receptores de arranque y recordatorios: procesamiento fuera del hilo principal con finalizacion de `goAsync` garantizada. La programacion al volver a la app y desde el canal de Flutter ya no ocupa la cola de lectura, escritura y autenticacion.
- Actualizador: DownloadManager elige su destino administrado. Se lee el archivo completado por descriptor y se copia, con limite de tamano, al almacenamiento interno para verificarlo. Ya no depende de crear `Android/data/.../files/Download`.
- Se mantienen los controles de tamano, SHA-256, paquete, version y certificado. Los fallos descartan las copias parciales y muestran mensajes comprensibles sin rutas internas.
- La consulta del estado de descarga no bloquea los controles ni reconstruye la pantalla si el estado no cambio.
- Novedades de 3.5.2: cuatro paginas, manteniendo su presentacion solo al actualizar y el recorrido inicial separado. Changelog en `release/3.5.2.md`.

## Pruebas

- 523 pruebas Flutter aprobadas; un benchmark opcional omitido. La suite incluye finanzas, importacion, cuotas, pagos parciales, borrado/deshacer, privacidad y actualizador.
- 157 pruebas nativas aprobadas; sin fallos, errores ni omisiones. La cobertura del actualizador incluye SDK 24, 28, 33 y 36, almacenamiento externo inaccesible, lectura por proveedor, archivos incompletos o demasiado grandes y digest incorrecto.
- Analizador: 0 errores, 0 advertencias y 451 avisos informativos preexistentes. Salida 0 con `--no-fatal-infos`.
- Matriz de actualizacion: 12 comprobaciones usando versiones instaladas 3.2.2+89, 3.5.0+97, 3.5.0+98, 3.5.1+99, 3.5.1+100 y 3.5.2+101. Las anteriores detectan la candidata 101; la 101 no se ofrece a si misma. Se uso una fuente de actualizacion de prueba, no una publicacion de la candidata.
- Cuatro pruebas visuales con fuentes reales, 320x640 y 390x844, tema claro y oscuro. Se acorto el texto final tras inspeccionar la pantalla de 320 px; capturas regeneradas y verificadas sin texto oculto tras el boton.
- 257 archivos de codigo, pruebas, assets y configuracion coinciden entre repositorio y staging; se excluye el registro generado de plugins.
- `git diff --check` aprobado. Cambios ajenos conservados. ADB sin dispositivos conectados.

## APK

- Archivo: `release/sin-rial-3.5.2-build101.apk`.
- Tamano: 70.308.679 bytes.
- Paquete: `com.lacaprichosa.app`; nombre Sin Rial; versionName 3.5.2; versionCode 101.
- No depurable; minSdk 24, targetSdk 36; ARM32, ARM64 y x86_64.
- SHA-256: `8b24af96d181d5731001ace43e9ac5b8d0c973c97dcc7de6002401864050cd42`.
- Firma v2 y alineacion ZIP de 16 KiB verificadas.
- Certificado SHA-256: `6e0965ff509debd2db0a5b628f6d55441457cf2fff320b44e70d2d33e62aa2a3`, comprobado contra el APK local de build 100. Se conserva el certificado existente para permitir actualizaciones sin desinstalar.
- Sin IntegrationTestPlugin en DEX ni en el registro de plugins de release.
- La copia entregada coincide por SHA-256 con el APK compilado en staging.

## Evidencia

Staging: `C:/Users/Arturo/AppData/Local/SinRialBuilds/finance-final-20260916-124535`.

- `build/test-build101-final.log`
- `build/native-build101-final.log` y `build/app/test-results/testDebugUnitTest`
- `build/analyze-build101-final.log`
- `build/visual-build101.log` y `build/release101-qa`
- `build/upgrade101-{89,97,98,99,100,101}.log`
- `build/apk-build101.log`

Compilacion: `flutter build apk --release --build-name=3.5.2 --build-number=101`, con regeneracion normal de plugins (sin `--no-pub`).

## Limites y entrega

- No se instalo en un Poco F3 ni en otro telefono fisico. El fallo de almacenamiento externo se reproduce mediante pruebas nativas; queda pendiente la comprobacion en el dispositivo afectado.
- No se midieron FPS ni tiempo de apertura en hardware. Las mejoras de rendimiento eliminan trabajo del hilo principal y actualizaciones de interfaz innecesarias; no se afirma un tiempo de inicio concreto.
- Android puede aplazar alarmas por restricciones de bateria, Doze o permisos. Se usa hora exacta cuando esta autorizada y una alternativa inexacta cuando no lo esta; no se promete entrega puntual bajo todas las restricciones del fabricante.
- Un telefono con el actualizador antiguo bloqueado necesita instalar manualmente este APK una vez, sobre la app existente y sin desinstalarla. Se recomienda una copia de seguridad antes de actualizar.
- Publicacion autorizada el 2026-11-09. Metadatos preparados para el tag `v3.5.2+101`; `release/latest.json` identifica el APK 101 y su SHA-256. El procedimiento de entrega verifica los assets del borrador antes de publicarlo y luego compara la descarga publica y el manifiesto sin autenticacion con los archivos locales.
