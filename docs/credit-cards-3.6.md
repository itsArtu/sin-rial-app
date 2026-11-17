# Credit cards and bank shortcuts

## Ledger contract

- Credit cards are accounts with `kind: credit`, never a second ledger.
- `balance` is negative for debt; available credit is limit plus balance.
- Consumption is an expense. A payment is a same-currency transfer from a non-credit account, not another expense.
- Initial debt, limit, minimum and closing/payment days are user-entered statement data. No interest or minimum-payment formula is invented.
- Payments reduce `creditMinimumDue`. A signed `creditMinimumBalance` retains excess payment coverage, so edit/delete/undo work in any order. Updating the statement minimum creates a new `creditMinimumCycle`; reversing an older-cycle payment does not change the new minimum.
- Liquid home balances, savings funding and debt-payment sources exclude credit cards.
- Currency account overviews also exclude credit cards. Selecting a bank account always opens that account. Home credit widgets are separate, show available credit and open the selected credit card.
- Selecting `Pago TDC` from an expense offers a credit-card selector only when cards exist. A linked payment becomes a transfer, debiting the bank once and reducing the selected card debt without another expense. Without cards, the legacy category remains an ordinary expense.
- Cards and their movements are included in existing encrypted state and portable backups. Only optional last four digits are stored, not PAN or CVV.
- The last-four field accepts at most four numeric digits, including paste; nonempty values must contain exactly four digits when saved. `cardholderName` is separate from the optional alias in `label`; display names keep the bank, with the alias in parentheses.

## Bank shortcuts

Known Android packages are verified against their Google Play listings:

- Venezuela: https://play.google.com/store/apps/details?id=com.bancodevenezuela.bdvdigital
- Mercantil: https://play.google.com/store/apps/details?id=com.mercantilbanco.mercantilmovil
- Provincial: https://play.google.com/store/apps/details?id=com.totaltexto.bancamovil
- Banesco: https://play.google.com/store/apps/details?id=com.banesco.samfbancamovilunificada
- Bancamiga: https://play.google.com/store/apps/details?id=com.bancamiga
- BNC: https://play.google.com/store/apps/details?id=bnc.bncnet.mobile2

The full verified catalog and fallback rules are in [bank-app-shortcuts.md](bank-app-shortcuts.md). There is no manual selector or installed-app enumeration. Launch uses the public launcher entry point without data URI or financial extras. If the app is absent, its Play listing opens; uncatalogued banks use a provider-name search. Legacy package overrides in backups are ignored. Calculator-only access cannot use this channel.

Android visibility reference: https://developer.android.com/training/package-visibility/declaring

## Visual assets

- Visa: https://commons.wikimedia.org/wiki/File:Visa_Inc._logo_(2021%E2%80%93present).svg
- Mastercard symbol, without wordmark: https://commons.wikimedia.org/wiki/File:Mastercard_2019_logo.svg
- Logos identify the card network; generic card designs do not imply bank affiliation.
- Partner assets: Rio logo from https://instaleap-data-client.s3.us-east-1.amazonaws.com/RIO_SUPERMARKET/RioLogo.png (Rio Market storefront); Zona Tech from https://zonatechgroup.com/wp-content/themes/zt-nueva-era/assets/brand/logo-white.svg ; SoyTechno from https://brandfetch.com/soytechno.com . Partner designs identify the merchant separately from the bank and network. SoyTechno supports Visa and Mastercard; Rio and Zona Tech are restricted to Mastercard, including save validation.
- Franchise designs use separate Visa/Mastercard palettes and motifs. Visa offers Standard (Classic in the lockup), Gold, Platinum and Signature. Mastercard offers Standard, Gold, Platinum and Black. Legacy Visa records saved as Black display as Signature and normalize on edit, without changing debt, limit or movements. Switching the network converts Signature/Black to the matching tier. Bank and co-brand designs remain available separately.
- Reference catalogs: https://www.mastercard.com/lac/es/personal/find-a-card/credit-card.html and https://caribbean.visa.com/pay-with-visa/find-a-card/credit-cards.html . The Gold references supplied by the user guide the Visa lockup and Mastercard radial engraving; no cardholder identity or card number is copied.
- Manrope static weights 400/500/600/700/800 were instantiated from the existing bundled variable font using fontTools, with updated name tables and unchanged source timestamp. The existing OFL license is retained.

## Compatibility boundaries

Android bank shortcuts need installed, launchable bank apps. This feature does not authorize transactions. Card payment currently requires a source account in the card's currency. Closing/payment day 29-31 clamps to the last valid day in short months.

## Indexed credit and actual transfer fees (build 106)

- `creditBasis` defaults to nominal for existing records. UVC must be explicitly selected. The form accepts debt and available credit in UVC, using the latest valid official BCV IDI without an editable IDI field. It is not the USD exchange rate.
- `creditUnits` stores signed decimal units as text, with up to 24 decimal places on division. `creditIndex` and `creditIndexDate` identify the confirmed valuation; index history is retained.
- Each indexed movement retains its original index and unit delta. Edits and reversals remove those units even after valuation changes. Full payments clear fractional unit residue.
- The official BCV index table is fetched in the background, at most once per successful day, with coalesced requests, timeouts and retry throttling. The parser selects the current-expression IDI column, not USD or the obsolete index. Future and invalid quotes are rejected; failed requests retain the last valid valuation and its date. Index parsing runs outside the UI isolate.
- Indexed debt and limit are stored as decimal UVC units. Both are revalued from the latest eligible IDI without creating movements or debiting liquid accounts. Legacy nominal snapshots are converted using their previous confirmed index before applying a newer index. New operations need a quote for their date, at most seven days old. Existing operations retain their original unit delta for reversal.
- Updating an approved limit appends `creditLimitHistory` and never creates income or changes debt. Indexed limit updates also maintain `creditLimitUnits`. Ordinary consumption is entered by the user; no automatic expense, interest or tariff is inferred from index changes.
- Credit-to-Ubii uses gross source debt, net destination balance and a deducted fee equal to the difference. Example: 10000 -> 9650, fee 350 / 3.5%. This is arithmetic from actual amounts, not a universal Ubii tariff.
- Direct advances default off and must be enabled from confirmed card conditions. BNC SoyTechno rejects direct advances even with an imported enabled flag. Recording a completed Ubii top-up does not assert that every card is eligible for it.
- The five automations never send banking instructions. Suggestions and budgets require acceptance, duplicate warnings can be overridden, and card reminders are grouped/deduplicated. Scheduled portable backups use the Android-selected persistent folder permission and password stored only in the encrypted device state; those settings are excluded from exported backups. They run while the app is active, not as a guaranteed background job.

## Official product checks, 2026-11-16

| Product | Confirmed information | Not assumed |
| --- | --- | --- |
| Bancamiga | Its credit-card page describes revolving UVC, IDI adjustment, 12-month financing and a published annual interest rate. | Applicability to every co-branded card, current individualized interest/fees, and cash-advance eligibility. |
| BNC SoyTechno | Official FAQ says no cash advances, no commission on purchases/consumption, six-month financing and possible limit increases. | UVC status not explicitly confirmed by that FAQ; use the contract. |
| BDV digital card | Official announcement offers Efectivoclave on eligible digital cards. | No universal UVC setting or invented Efectivoclave fee. Do not confuse the card with the separate commercial Credito Digital product. |
| Mercantil Venezuela | Official Mastercard page describes card financing and links to Prestame. Prestame is a separate line. | Panama rates, universal UVC classification, or a fixed cash-advance fee. |
| Bancaribe | Official card product page found. | No verified universal UVC/fee rule; contract controls. |
| Ubii | The net-received workflow is supported. | No current universal fee verified; use the actual gross/net amounts. |

Sources:
- https://www.bancamiga.com/tarjeta-de-credito/
- https://www.bancamiga.com/tasas-y-tarifas/
- https://www.bncenlinea.com/productos-y-servicios/tarjeta-soytechno
- https://www.bancodevenezuela.com/index.html%40p%3D22210.html
- https://www.mercantilbanco.com/personas/productos/tarjetas/tarjeta-credito-mastercard-mercantil
- https://chatbot.mercantilbanco.com/mercprod/content/privada/tarjetas/prestame.html
- https://www.bancaribe.com.ve/tarjeta-de-credito-bancaribe
- https://www.bcv.org.ve/estadisticas/indice-de-inversion (retrieved on 2026-11-17: current-expression IDI 4.47704199; the separate USD column was 915.74760000)

The reviewed February/March Bancamiga and April BDV tariff PDFs are not treated as current November tariff tables. No historical published percentage is silently applied to user transactions.

Card artwork is an in-app representation inspired by the supplied references, not a reproduction of official card artwork. Co-brand names are based on official issuer announcements; selecting a design does not establish eligibility or change a contract.
