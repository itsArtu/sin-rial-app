# Sin Rial 3.2.1 - Build 87 (prueba local)

## Cambios sobre build 86

- Logo de bloqueo de 56 px con entrada por opacidad y desplazamiento de 6 px.
  No cambia de escala al aparecer el teclado ni reinicia al escribir el PIN.
  La lista conserva su posicion superior; sigue desplazandose si hace falta
  para mantener visible el boton de desbloqueo.
- Icono del recorrido con entrada independiente, giro suave y asentamiento.
  Duracion finita de 1100 ms, controlador liberado al salir y sin bucles.
  Logo e icono respetan movimiento reducido. Omitir sigue disponible en cada paso.
- Apariencia permite elegir por separado el color de ingresos y gastos,
  con vista previa y restauracion individual. Valores antiguos o invalidos
  conservan los colores predeterminados.
- Colores aplicados a resumen, historial, detalle, acciones de cuenta,
  recurrentes, movimientos vinculados y widget Android. Los errores, eliminar,
  deuda pagada y variaciones de tasas conservan sus colores semanticos.
- Logos compartidos con margenes mas reducidos, fondo neutro para marcas,
  simbolos de efectivo y billetera, e identificador de Cestaticket Alimentacion
  o Integral. Codigos normalizados y sustituto si una imagen no carga.
- Imagenes de cuentas decodificadas segun tamano fisico, con ancho maximo
  de 256 px y filtrado medio. Se reutilizan los archivos de marca existentes.

## Limpieza comprobada

Eliminados cinco componentes sin referencias en lib, test ni integration_test:
ThemeToggleButton, PrivacyToggleButton, AccountDistributionCard,
CurrencyAccountSummaryLine y AccountMiniCard. Tambien se retiro logoText,
cuyo ultimo consumidor fue sustituido por iconos de cuenta.

LogoBadge se movio a account_logos.dart; no se elimino su funcionalidad.
No se borraron migraciones, compatibilidad de historicos, datos financieros,
dependencias ni recursos por suponer que no se utilizaban.
Esta revision no afirma que todo el repositorio este libre de codigo prescindible.

## Verificacion

- Flutter: 396 pruebas aprobadas; 1 benchmark optativo omitido.
- Android/JVM: 125 pruebas, 0 fallos, 0 errores, 0 omitidas.
- Apariencia: 10 pruebas focalizadas aprobadas despues de la limpieza final.
- Visual: 16 pruebas aprobadas con fuentes reales y PNG precargados.
  Capturas a 320 y 390 px, claro/oscuro y selector con texto al 160%.
- Inspeccion visual: bloqueo con teclado, Apariencia, selector de color y
  galeria de bancos, billeteras, efectivo y ambos Cestaticket.
- Pruebas de persistencia Flutter y SQLite Android, valores invalidos,
  colores semanticos independientes, widgets en dos tamanos,
  estabilidad geometrica del logo y controladores detenidos al terminar.
- Analisis estatico: 0 errores y 0 advertencias; 435 avisos informativos.
- git diff --check aprobado.
- No se ha perfilado un cambio de tiempo de arranque, RAM total o bateria
  en el dispositivo. Reducir decodificacion y detener animaciones no equivale
  a haber medido esas metricas.

## Evidencia

En build del workspace de staging: test-build87.log, native-test-build87.log,
analyze-build87.log, appearance-test.log, visual-build87.log, apk-build87.log,
appearance-qa/ y october-qa/.

No se publica en GitHub ni se modifica release/latest.json.

## APK e instalacion

- Archivo: release/sin-rial-3.2.1-prueba-build87.apk; 65,981,655 bytes.
- SHA-256: 8b630173725b5f125adb364ffb79680962efcccb1808f0cc85e212c9387c087c.
- versionName 3.2.1, versionCode 87, minSdk 24, targetSdk 36.
- Release no depurable, firma v2 con el mismo certificado de build 86.
- Alineacion ZIP de 16 KiB aprobada; arm64-v8a, armeabi-v7a y x86_64.
- adb install -r: Success en 24069PC21G. Version instalada confirmada como 87.
- firstInstallTime conservado: 2026-10-06 10:36:49.
- SHA-256 del base.apk instalado coincide con el archivo local.
- MainActivity: Status ok; captura del inicio con contenido visible.
  No se encontraron errores Flutter ni excepciones fatales en el registro
  del proceso inspeccionado.
- El dispositivo deniega inyeccion de toques por ADB (INJECT_EVENTS).
  No se cambiaron permisos para eludirlo. Se pudo leer la jerarquia de
  Apariencia, incluidos los dos nuevos controles, pero la navegacion
  automatizada completa se valido con fixtures, no con toques en el telefono.
- No se ingreso PIN, se desinstalo la app ni se crearon movimientos de prueba.
