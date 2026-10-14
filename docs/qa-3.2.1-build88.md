# Sin Rial 3.2.1 - Build 88 (prueba local)

## Cambios sobre build 87

- Selector de colores de movimientos como lista vertical, con muestra cuadrada,
  importe positivo o negativo y marca de seleccion. No reutiliza la cuadricula
  del color del tema. Restauracion individual y seleccion persistente conservadas.
- Referencia bancaria opcional para nuevos ingresos y gastos, solo si esta
  activada en Ajustes. Se conserva la clave persistida askExpenseReference por
  compatibilidad; permanece desactivada de forma predeterminada. Sin temporizador.
  Editar un ingreso permite modificar su referencia sin volver a preguntar.
- Credito de Acerca de centrado bajo el logo y la version, incluso al envolver
  el texto en pantallas pequenas o con fuente ampliada.
- Graficas USD, EUR y USDT seleccionan el dato real mas cercano desde cualquier
  zona del grafico. La informacion sigue visible al soltar. Un solo registro
  aparece como punto seleccionable, sin generar tasas ficticias. La fecha de
  USDT utiliza Caracas y la seleccion se reinicia cuando cambia el historial.
- Recorrido de novedades actualizado; build 88 se presenta una vez y conserva
  Omitir. No se mezcla con el recorrido inicial de usuarios nuevos.

## Verificacion

- Flutter: 411 pruebas aprobadas; 1 benchmark optativo omitido.
- Visual y focalizada: 35 pruebas aprobadas con fuentes reales.
- 15 pruebas nuevas: referencia de ingresos activada/desactivada, ceros iniciales,
  espera sin timeout, edicion sin duplicar movimientos ni alterar saldos,
  colores independientes del tema, credito centrado y graficas con 0/1/2/7 datos.
- Inspeccion de imagenes: selector de gastos, Acerca de con texto al 160% y
  tooltip de USDT. Pruebas de ajuste a 320 y 390 px, claro/oscuro y texto ampliado.
- Analisis estatico: 0 errores y 0 advertencias; 430 avisos informativos.
- No hubo cambios nativos en este ajuste; no se repitio la suite Android/JVM.
- git diff --check aprobado.

## APK e instalacion

- Archivo: release/sin-rial-3.2.1-prueba-build88.apk; 66,014,423 bytes.
- SHA-256: 0fe4c144852e72eded89ea1e2ad79d06b469f37e702134392045fb2275dfc3da.
- versionName 3.2.1, versionCode 88, minSdk 24, targetSdk 36.
- Release no depurable, firma v2 con el certificado historico de build 87.
- Alineacion ZIP de 16 KiB aprobada; arm64-v8a, armeabi-v7a y x86_64.
- adb install -r: Success en 24069PC21G, Android 16; version instalada 88.
- firstInstallTime conservado: 2026-10-06 10:36:49.
- SHA-256 de base.apk instalado coincide con la APK local.
- Inicio de MainActivity: Status ok; Android llevo al controlador de permisos.
  Sin errores Flutter ni excepciones fatales en el registro del proceso revisado.
- El dispositivo deniega la inyeccion de toques por ADB, por lo que los flujos
  interactivos se validaron con pruebas de widgets y fixtures, no navegando
  toda la aplicacion en el telefono. No se eludieron permisos ni autenticacion.
- No se ingreso PIN, se borraron datos ni se crearon movimientos en el telefono.

## Evidencia

En build del workspace de staging: test-build88.log, visual-build88.log,
analyze-build88.log, apk-build88.log y appearance-qa/.

No se publica en GitHub ni se modifica release/latest.json.
