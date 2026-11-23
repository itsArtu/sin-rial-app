# Sin Rial 3.6.2 / build 113

Revisión del 23 de noviembre de 2026. Publicación autorizada por el usuario tras validar las correcciones.

## Cambios finales

- Inicio vuelve al balance sin recuadro exterior y al gráfico de extremo a extremo.
- Banco de Venezuela: fondo de dos tonos grises y piezas de colores escalonadas según la referencia; identificación habitual de la app, sin encabezado BDV incrustado ni marcas Mastercard/Maestro añadidas. Datos financieros legibles en crédito.
- OKX: logo de píxeles y textura de rectángulos oscuros; sin VISA ni Platinum, según la última indicación del usuario.
- Novedades: Siguiente y Empezar centrados, con el mismo ancho en todos los pasos. Anterior queda junto al indicador de páginas.
- Se conservan las mejoras de cuentas, movimientos, selector de hora, navegación, UVC y protección del historial validadas en build 112. La personalización de diseños sigue siendo exclusiva de las tarjetas de crédito.

## Validación

- Suite Flutter completa: 620 aprobadas, 0 fallidas, 1 omitida.
- Pruebas nativas propias de Android: 175 aprobadas en 14 suites; 0 fallos, errores u omisiones.
- Análisis estático de lib y test: 0 errores, 0 advertencias y 488 observaciones informativas.
- Inicio: pruebas de gráfico a todo el ancho en 320 y 390 px, ambos temas. Capturas con tipografía real y texto ampliado.
- Tarjetas: capturas BDV, OKX y crédito BDV en 320, 390 y 412 px; chip/contactless, moneda y datos contenidos.
- Novedades: navegación completa, atrás y finalización en 320x640 y 390x844, ambos temas, texto al 160 %. Geometría del botón y su texto centradas.
- Las regresiones UVC comprueban actualización al desbloquear y por temporizador, conservación de unidades y límite aprobado, rechazo de fechas futuras e historial inválido. La consulta de la fuente en vivo se documentó en la revisión build 112.

No se conectó un teléfono para esta revisión. Las pruebas de widgets verifican navegación y geometría; no sustituyen una medición de fluidez en hardware real.

La carpeta de trabajo conserva full-113.log, native-113.log, analyze-113.log, home-113.log, visual-113.log, cards-113-final.log y build/design-qa/. El código se sincroniza al repositorio antes de publicar.

## APK verificada

- Paquete: com.lacaprichosa.app; versionName 3.6.2; versionCode 113.
- Android mínimo API 24, objetivo API 36; ARM32, ARM64 y x86_64.
- Tamaño: 73877815 bytes.
- SHA-256: 104f1f7c4f703873d8470188996b84c6744b836a72c775486f136dd6d23601f5.
- Firma v2 válida; certificado SHA-256 6e0965ff509debd2db0a5b628f6d55441457cf2fff320b44e70d2d33e62aa2a3, idéntico al de la APK pública build 106 descargada para esta revisión.
- Alineación ZIP de 16 KiB aprobada; DEX sin IntegrationTestPlugin.
- Artefactos: sin-rial-3.6.2-build113.apk, su archivo .sha256 y latest.json.

Matriz del actualizador ejecutada con versiones instaladas 3.5.1+100, 3.6.1+106, 110, 111, 112 y 3.6.2+113: las seis ejecuciones pasaron; ofrece 113 a las anteriores y no se ofrece a sí misma. Los logs quedan en la carpeta separada sin-rial-updater113-20261123.
