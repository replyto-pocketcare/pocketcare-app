package care.pocket.domain.receipts

// Ported from packages/core/receipts/src/fixtures.ts (P1.5a). Only the
// `name`/`text`/`currency` fields are reproduced here -- the TS file's
// `expect` blocks aren't needed on the native side because correctness is
// judged against the actual exported golden vectors (which already encode
// the expected parse output), not against a second copy of the expectation.
// Transcribed character-for-character from the TS source's template
// strings, including exact whitespace/newlines, since parseReceiptText's
// vectors were exported by running the REAL text through the REAL parser --
// any drift here would silently test a different receipt than the vector
// was generated from.

data class ReceiptFixture(val name: String, val text: String, val currency: String)

val RECEIPT_FIXTURES: List<ReceiptFixture> = listOf(
    ReceiptFixture(
        name = "indian-restaurant-gst-and-service-charge",
        currency = "INR",
        text = "\nSPICE GARDEN RESTAURANT\n12 MG Road, Bengaluru 560001\nGSTIN: 29AABCS1234F1Z5\nTax Invoice\nBill No: 4471          Table: 12\nDate: 25/07/2026  Time: 21:14\n--------------------------------\nItem              Qty   Amount\n--------------------------------\nPaneer Tikka        1    320.00\nButter Naan         4    180.00\nCold Coffee         2    120.00\nVeg Biryani         1    280.00\n--------------------------------\nSub Total                900.00\nService Charge 5%         45.00\nCGST 2.5%                 23.63\nSGST 2.5%                 23.63\n--------------------------------\nGrand Total              992.26\n--------------------------------\nCash                    1000.00\nChange                     7.74\nThank you! Visit again\n",
    ),
    ReceiptFixture(
        name = "grocery-qty-rate-amount-columns",
        currency = "INR",
        text = "\nFRESH MART SUPERMARKET\nShop 4, Sector 18\nGST No 27AAAAA0000A1Z0\nDate 12/06/2026\nDescription        Qty   Rate   Amount\nBasmati Rice 5 kg    1  450.00  450.00\nToor Dal             2   95.50  191.00\nAmul Milk 1L         3   68.00  204.00\nSunflower Oil        1  185.00  185.00\nBritannia Bread      2   45.00   90.00\nTotal Qty: 9\nSub Total                       1120.00\nDiscount                          50.00\nCGST                              26.25\nSGST                              26.25\nGrand Total                     1122.50\nPaid by UPI\n",
    ),
    ReceiptFixture(
        name = "cafe-with-tip-usd",
        currency = "USD",
        text = "\nTHE CORNER CAFE\nDate: 03/04/2026\nFlat White             \$4.50\nAlmond Croissant       \$3.75\nAvocado Toast          \$9.00\nSubtotal              \$17.25\nTax                    \$1.55\nTip                    \$3.45\nTotal                 \$22.25\nVisa ****4412\n",
    ),
    ReceiptFixture(
        name = "kirana-x-quantity-notation",
        currency = "INR",
        text = "\nSHREE BALAJI STORES\n25-07-2026\n2 x Maggi Noodles        28.00\n1 x Tata Salt            26.00\n3 x Parle-G Biscuit      30.00\n1.5 kg Onion             45.00\nTotal                   129.00\n",
    ),
    ReceiptFixture(
        name = "round-off-adjustment",
        currency = "INR",
        text = "\nQUICK BITE\nDate 01/07/2026\nMasala Dosa            120.00\nFilter Coffee           40.00\nSub Total              160.00\nCGST 2.5%                4.00\nSGST 2.5%                4.00\nRound Off                0.60\nGrand Total            168.60\n",
    ),
    ReceiptFixture(
        name = "no-total-printed-derives-from-subtotal",
        currency = "INR",
        text = "\nSTREET FOOD CORNER\nPav Bhaji               90.00\nVada Pav                30.00\nSub Total              120.00\n",
    ),
    ReceiptFixture(
        name = "european-decimal-comma-dutch",
        currency = "EUR",
        text = "\nCAFE AMSTERDAM\nDatum 14-05-2026\nCappuccino              3,50\nAppeltaart              4,20\nMineraalwater           2,30\nSubtotaal              10,00\nBTW 19%                 1,90\nTotaal                 11,90\n",
    ),
    ReceiptFixture(
        name = "delivery-with-packaging-and-discount",
        currency = "INR",
        text = "\nURBAN TIFFIN\nOrder No: 88213\nDate: 20/07/2026\nPaneer Roll x2         240.00\nVeg Thali               180.00\nItem Total              420.00\nPackaging Charge         20.00\nDelivery Fee             35.00\nDiscount                 60.00\nGST                      22.75\nGrand Total             437.75\n",
    ),
    ReceiptFixture(
        name = "noisy-ocr-artifacts",
        currency = "INR",
        text = "\n~~~~ HOTEL SANGAM ~~~~\nPh: 080-4455 6677\nFSSAI 12345678901234\nDate : 18/07/2026\n================================\nChicken Biryani     1    340.00\nRaita               1     60.00\n================================\nSub Total                400.00\nService Charge            40.00\nCGST 2.5%                 11.00\nSGST 2.5%                 11.00\n================================\nTOTAL                    462.00\n================================\nPayment Mode : Card\nCustomer Copy\n",
    ),
    ReceiptFixture(
        name = "mismatch-must-not-silently-balance",
        currency = "INR",
        text = "\nBROKEN PRINT CAFE\nDate 10/07/2026\nSandwich               150.00\nJuice                   80.00\nGrand Total            300.00\n",
    ),
)
