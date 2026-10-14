# Sin Rial 3.2.1 - Build 85 (prueba local)

## Alcance

- Arranque con el color guardado; logo de Banesco proporcionado por el usuario.
- Apariencia y colores en una pantalla, con muestras alineadas.
- Importes de cuentas alineados a la derecha.
- Creacion de categorias desde el buscador, incluso sin resultados.
- Chucherias y sus palabras clave; reconocimiento del token TDC.
- Recarga saldo y Pago TDC sin metodo ni comision en nuevos gastos.
- Pagos asociados a una cuota concreta, incluyendo edicion, eliminacion y deshacer.
- Recordatorios nativos respetan las cuotas pendientes aunque se paguen fuera de orden.
- Ingreso opcional de prestamos en una cuenta compatible, sin liquidar la deuda y sin Cashea.
- Widget USDT de 2 columnas por 1 fila.
- Calculadora independiente sin autenticacion: solo recibe tasas y apariencia.
  El canal nativo rechaza lectura/escritura de datos financieros desde esa ventana.
  Abrir la app completa fuerza la comprobacion de seguridad configurada.
- Planificacion separa total, partidas y gastos sin asignar; permite asignarlos sin
  recalcular saldos, comisiones ni abonos historicos. Comparacion en USD con limite
  original visible cuando la partida usa otra moneda.

## Verificacion

- Flutter: 376 pruebas aprobadas; 1 prueba optativa omitida.
- Android/JVM: 124 pruebas aprobadas, sin fallos ni omitidas.
- Revision visual: 6 pruebas adicionales con capturas, a 320 y 390 px, claro/oscuro.
- Analisis estatico: sin errores ni advertencias; quedan avisos informativos de estilo.
- Las pruebas usan datos sinteticos. No se registran operaciones en el telefono real.
- Publicacion en GitHub y actualizacion del feed: no realizadas; entrega solo de prueba.

La evidencia local de compilacion, pruebas y capturas se guarda en el directorio
build del workspace de staging fuera de OneDrive.

## APK e instalacion

- Archivo: release/sin-rial-3.2.1-prueba-build85.apk; 65,981,103 bytes.
- SHA-256: bb310eca1e866afc69ddba2206470951012b8065bd6cd2e33c38d94f78f48639.
- Android: versionName 3.2.1, versionCode 85, minSdk 24, targetSdk 36.
- Firma v2 verificada, mismo certificado que la APK 3.2/build84 del telefono.
- Alineacion ZIP de 16 KiB verificada; APK release no depurable.
- Instalacion con adb install -r: Success en 24069PC21G / Android 16.
- versionCode 85 confirmado; firstInstallTime conservado (2026-10-06).
- Apertura de MainActivity: Status ok. No se desinstalo ni se borraron datos.
