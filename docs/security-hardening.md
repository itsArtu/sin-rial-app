# Seguridad del almacenamiento y del PIN

## Estado actual

El registro financiero utiliza SQLite nativo de Android (sin_rial_finance.db).
NativeJsonStore conserva su nombre y contrato JSON con Flutter, pero todas las
lecturas y escrituras financieras pasan por SqliteStateStore. WorkManager sigue
usando su propia base independiente.

- Tablas separadas para cuentas, movimientos, deudas, presupuestos, planes,
  metas, tarjetas, ajustes, fondos de ahorro, ahorros de pareja y bolsos.
  Cada entidad es una fila con identificador opaco y contenido JSON cifrado;
  NO es un unico JSON de todos los movimientos dentro de una celda.
- Configuracion, perfil, seguridad y tasas en metadatos cifrados. El esquema,
  orden y cantidad de filas son visibles; los nombres, saldos y descripciones
  no. Es cifrado por registro, no cifrado integral del archivo con SQLCipher.
- Transacciones atomicas para cambios de saldo, movimientos y demas colecciones
  del mismo guardado, WAL y synchronous=FULL. Los registros sin cambios conservan
  su ciphertext, incluso al cambiar de posicion; no se reescribe todo el historial.
- Los widgets de tasas leen solo metadatos y los avisos consultan solo deudas.
  Los calculos financieros de Flutter mantienen su comportamiento anterior.

- Valores cifrados mediante AES-256-GCM; clave no exportable en Android Keystore.
- Nonce nuevo por escritura y autenticacion del nombre/version del registro.
- Migracion desde JSON antiguo (completo/dividido) o preferencias cifradas:
  importar en transaccion, comparar todos los campos/colecciones, confirmar,
  releer/verificar y solo entonces retirar las copias anteriores. Una interrupcion
  antes de confirmar revierte la transaccion. Una interrupcion durante la limpieza
  reanuda la limpieza sin importar otra vez ni duplicar registros.
- Un manifiesto cifrado autentica el numero, orden e integridad de las filas.
  Detecta registros borrados o intercambiados, ademas de los errores de AES-GCM.
  El manejador de corrupcion NO borra/recrea la base; un marcador impide tratar
  una base desaparecida tras la migracion como una instalacion nueva.
  Las preferencias operativas de recordatorios y alarmas no se vacian.
- Un error de lectura, clave o autenticacion NO crea un estado nuevo. Se muestra
  una pantalla para reintentar. Un guardado fallido NO usa un fallback sin cifrar.
- PIN: PBKDF2-HMAC-SHA256 con 600000 iteraciones, sal aleatoria de 32 bytes.
  Android 7 usa la fabrica disponible PBKDF2-HMAC-SHA1 con 1400000 iteraciones;
  se actualiza al algoritmo SHA256 tras verificar el PIN en Android 8 o posterior.
- Los PIN antiguos SHA256 se migran al verificarlos correctamente, sin cambiar
  sus digitos. Comparacion con MessageDigest.isEqual.
- Desde el quinto error se esperan 30 segundos, aumentando hasta 15 minutos.
  Los contadores son persistentes, el reloj es monotono dentro del mismo arranque
  y una escritura Flutter antigua no puede reemplazar la seguridad nativa.
- La verificacion costosa se ejecuta fuera del hilo de interfaz.
- Proteccion de la ventana mientras esta bloqueada o se verifica el bloqueo
  al regresar a primer plano. La vista cubierta se excluye de accesibilidad.
- La privacidad en multitarea es opcional y esta desactivada por defecto, tanto
  para instalaciones nuevas como anteriores. Ajustes > Seguridad permite ocultar
  la vista en recientes, segundo plano y al bajar las notificaciones. No cambia
  el PIN, la biometria ni el bloqueo tras apagar la pantalla o superar la espera.
  Las capturas voluntarias siguen disponibles con la app desbloqueada y activa.
- Notificaciones de deudas marcadas como privadas en la pantalla bloqueada.
- Enlaces externos de actualizacion limitados a HTTPS.

## Limites y recuperacion

Esto protege datos en reposo y el acceso normal a la interfaz. No es una garantia
contra un telefono rooteado, un proceso comprometido, instrumentacion o la captura
fisica de una pantalla desbloqueada. La clave del almacen no exige biometria para
cada uso: los servicios de tasas, avisos y widgets necesitan acceder en segundo
plano. La biometria verifica la identidad mediante el sistema operativo.

Los respaldos automaticos y las transferencias del almacen estan excluidos porque
Android Keystore no traslada su clave a otro telefono. Desinstalar o borrar los
datos elimina el acceso local. Un PDF NO es un respaldo restaurable. Antes de una
distribucion amplia conviene implementar exportacion/importacion de un respaldo
cifrado portable con una contrasena elegida por el usuario.

La firma de APK NO se cambio. Cambiarla sin una estrategia de continuidad puede
impedir actualizar instalaciones existentes. Sigue pendiente la decision de firma
de produccion y la custodia de esa clave.

## Verificacion

El acceso rapido de widgets usa una Activity privada, un motor Flutter separado
y el mismo editor y validaciones del libro de cuentas. Respeta PIN/biometria y
oculta el contenido en segundo plano. Solo se cierra tras confirmar el guardado.
SQLite guarda una revision de interfaz dentro de los metadatos cifrados: cada
ventana escribe con la revision que leyo. Una escritura antigua se rechaza de
forma atomica, sin sobrescribir movimientos de la otra ventana. La app recarga
los datos al volver al primer plano. Las actualizaciones nativas de tasas no
invalidan esta revision y conservan su proteccion contra snapshots antiguos.

Pruebas de host: AES/GCM real con clave de prueba, migracion antigua/dividida,
retencion de datos al fallar, deteccion de adulteracion/clave incorrecta/registro
intercambiado, migracion de PIN, persistencia de esperas y compatibilidad Android
7. Las pruebas Flutter cubren fallos de lectura/escritura, PIN asincrono, bloqueo
del acceso desde widgets, regreso desde segundo plano y formato del bloqueo.

Las pruebas SQLite cubren ambos formatos antiguos, equivalencia completa,
transacciones fallidas, limpieza interrumpida, datos adulterados, archivo corrupto,
base desaparecida, esquemas futuros, Android 7, actualizaciones concurrentes,
altas/ediciones/bajas/reordenamiento y un historial de 2500 movimientos. La prueba
del canal Flutter verifica el transporte separado de planes, pareja y bolsos.

Queda una comprobacion en telefono real de Android Keystore/biometria,
actualizacion sobre una instalacion existente, reinicio, miniatura de recientes y
los lanzadores del fabricante. Las pruebas de host no reemplazan esa validacion.
