# Tarifas consultadas: 6 de octubre de 2026

## Cestaticket

Fuente oficial: https://cestaticket.com.ve/ticket-bienestar-plus

Ticket Bienestar Plus admite avances de efectivo en cajeros Cirrus, sujetos
a los parametros de las entidades financieras. Esta pagina no publica una
comision unica por retiro/transferencia. El nombre Integral en la app responde
a la denominacion solicitada por el usuario; no se afirma que sea el nombre
comercial oficial de Plus.

Fuente Alimentacion: https://cestaticket.com.ve/ticket-bienestar-alimentacion

Implementacion: dos cuentas diferenciadas por benefitType. Alimentacion solo
admite tarjeta para egresos, no transferencias salientes. Integral permite
registrar transferencias/retiros hacia otra cuenta o efectivo, con comision
manual fija/porcentual, tarifa previamente confirmada o Sin comision explicito.
No se inventa un porcentaje ni se usa el mantenimiento de un banco para esta
tarjeta.

Build83: en gastos, Alimentacion ofrece solo Tarjeta e Integral ofrece
Tarjeta y Transferencia bancaria, segun confirmacion del usuario. No se
inventa una comision de pago de Integral.

## Mantenimiento bancario

Fuente oficial Banesco, vigente desde 21/09/2026:
https://banesco-prod-2020.s3.amazonaws.com/wp-content/uploads/tarifas-productos-servicios-banesco.pdf

Pagina 1: cuentas corrientes activas, persona natural, Bs. 684,00 como LIMITE
MAXIMO mensual. Persona juridica: Bs. 6.839,00. No equivalen a un cobro universal
efectivo de todos los bancos. La seccion de ahorro no lista mantenimiento.
No trasladar estas cifras a cuentas USD, pensionados o productos exentos.

Tambien se revisaron el tarifario BDV de abril de 2026 y Bancamiga de septiembre
de 2025: anteriores a la actualizacion de septiembre de 2026, no adecuados para
autocompletar una tarifa actual. El enlace PDF anterior de Mercantil redirige a
su pagina de tarifas. No se incorpora una cifra no comprobada.

## Regla aplicada

- Build83, por solicitud confirmada del usuario: automatico en cuentas
  nacionales identificadas como Corriente y VES de personas naturales.
  Importe Bs. 684; la pantalla aclara que es el maximo publicado y que el
  cobro real puede variar. No se afirma que sea una tarifa bancaria universal.
- Excluye ahorro, USD, cuentas sin tipo confirmado, efectivo y Cestaticket.
- Las cuentas existentes elegibles adoptan la politica desde el proximo mes.
  Las reglas manuales de build82 fuera de ese alcance dejan de ejecutarse.
- Primera fecha: primer dia del siguiente mes. Sin cobros retroactivos.
- Si Android no pudo ejecutar la tarea, se registra solamente el mes actual
  al volver a abrir/reanudar. No se recuperan cargos de meses omitidos.
- Descuento local del balance, NO una orden ni debito al banco real.
- Un movimiento editable/eliminable por cuenta y mes, categoria Comisiones
  bancarias. SQLite guarda balance, movimiento y cursor en una transaccion.
- Eliminar/editar el gasto no lo regenera. Cambiar la cuenta a un tipo/moneda
  no elegible detiene los siguientes. No hay interruptor de activacion.
- La alarma diaria existente comparte esta tarea, aunque los avisos esten
  desactivados. Android puede retrasar alarmas por ahorro de bateria o impedirlas
  tras Forzar detencion; no se promete ejecucion exacta a medianoche.

## Cumpleanos y privacidad

Saludo anual automatico a la hora del recordatorio configurado, sin edad ni fecha
de nacimiento en el aviso. 29 de febrero se celebra el 28 en anos no bisiestos.
No se duplica en el mismo ano. Respeta el permiso de notificaciones del sistema.
No se anuncia el saludo en el tour ni en el perfil.
