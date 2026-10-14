# Sin Rial 3.2.1 - Build 86 (prueba local)

## Cambios sobre build 85

- Presupuesto con una sola fila, total y limite por categoria.
- Sin subcategorias ni selector de partidas al registrar movimientos.
- Los planes anteriores se agrupan al mostrarse. Al editar/copiar se consolidan
  sus limites por categoria; los limites de monedas distintas se convierten a USD
  con las tasas visibles actuales. El guardado admite deshacer.
- Cuentas, movimientos y metadatos historicos no se migran ni se eliminan.
- Selector compartido con Crear categoria fijo, incluso en busquedas sin resultados.
- El editor evita agregar una categoria que ya tenga limite en el plan.
- PDF sin tabla de partidas ni etiquetas de partidas en el detalle.
- Recorrido de cinco pantallas ligado a version y compilacion, con Omitir en cada
  paso. Completar u omitir queda guardado. Usuarios nuevos conservan su recorrido
  general, sin encadenarlo al de novedades. Ambos respetan el bloqueo.
- Logos e iconos con entrada breve, sin animaciones repetitivas y respetando
  movimiento reducido. Pie del recorrido con altura estable.

## Rendimiento

- Eliminada la pantalla de asignacion de partidas y su recorrido de movimientos.
- El editor de limites no recalcula gastos. El resumen por categoria reutiliza
  la cache existente y evita calcular asignaciones antiguas cuando no se necesitan.
- Menos filas, indicadores y controladores en presupuesto y movimientos.
- Medicion optativa en Flutter test host con 10000 movimientos sinteticos:
  resumen en una pasada 186.82 ms; lectura de cache 0.00105 ms.
  Estas cifras no son tiempos de fotogramas Android ni comparan build 85 con 86.

## Verificacion

- Flutter: 386 pruebas aprobadas, 1 benchmark optativo omitido en la suite general.
- Android/JVM: 124 pruebas aprobadas, 0 errores, 0 fallos, 0 omitidas.
- Benchmark optativo: ejecutado por separado, aprobado.
- Visual/accesibilidad: 16 pruebas adicionales aprobadas, capturas claro/oscuro
  a 320 y 390 px, mas recorrido a 320 x 640 con texto al 150%.
- PNG del logo precargado antes de capturar; inspeccion visual de presupuesto,
  buscador de categorias y recorrido, incluyendo el logo visible.
- PDF de ejemplo renderizado e inspeccionado: resumen y detalle, sin partidas.
- Analisis estatico: 0 errores, 0 advertencias; 451 avisos informativos de estilo.
- No se crean operaciones financieras de prueba en el telefono.
- No se publica en GitHub ni se modifica release/latest.json.

## Evidencia

Logs y capturas en build del workspace de staging fuera de OneDrive:
test-build86.log, visual-build86.log, analyze-build86.log, performance-build86.log,
october-qa y budget-report-qa.

## APK e instalacion

- Archivo: release/sin-rial-3.2.1-prueba-build86.apk; 65,899,183 bytes.
- SHA-256: 4f48e41cc8d3c9717513ba36ccefdd62ecf2f16aa6e7d61e2171e5b962846320.
- versionName 3.2.1, versionCode 86, minSdk 24, targetSdk 36.
- Release no depurable, firma v2 con el mismo certificado de build 85.
- Alineacion ZIP de 16 KiB verificada. ABI arm64-v8a, armeabi-v7a y x86_64.
- adb install -r: Success en 24069PC21G / Android 16.
- firstInstallTime conservado: 2026-10-06 10:36:49.
- SHA-256 del base.apk instalado coincide con el archivo local.
- MainActivity abrio con Status ok; sin errores Flutter ni excepciones fatales
  en el registro del proceso inspeccionado. No se ingreso PIN ni se modificaron
  datos financieros para probar la interfaz en el telefono.
- Las comprobaciones completas de navegacion y contenido se realizaron con
  fixtures sinteticos; la apertura por ADB no equivale a un perfil de rendimiento.
