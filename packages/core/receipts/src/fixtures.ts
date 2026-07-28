/**
 * Receipt fixtures — anonymized text of the layouts this parser has to survive.
 *
 * These are transcriptions of real-world shapes (Indian restaurant bills,
 * kirana/supermarket grocery bills, a Western cafe receipt, a PDF text layer),
 * including the noise OCR leaves behind: payment footers, GSTIN lines, column
 * headers and separator rules.
 *
 * Adding a fixture whenever a real receipt misparses is how this feature stays
 * accurate over time. Treat a failing fixture as a release blocker.
 */

export interface Fixture {
  readonly name: string;
  readonly text: string;
  readonly currency: string;
  /** What a correct parse must produce. */
  readonly expect: {
    readonly merchant?: string;
    readonly occurredAt?: string | null;
    readonly currency?: string;
    readonly total: number | null;
    /** Must reconcile (Σ lines === total). */
    readonly balances: boolean;
    readonly itemCount?: number;
    readonly tax?: number;
    readonly serviceCharge?: number;
    readonly discount?: number;
    readonly tip?: number;
  };
}

export const FIXTURES: readonly Fixture[] = [
  {
    name: "indian-restaurant-gst-and-service-charge",
    currency: "INR",
    text: `
SPICE GARDEN RESTAURANT
12 MG Road, Bengaluru 560001
GSTIN: 29AABCS1234F1Z5
Tax Invoice
Bill No: 4471          Table: 12
Date: 25/07/2026  Time: 21:14
--------------------------------
Item              Qty   Amount
--------------------------------
Paneer Tikka        1    320.00
Butter Naan         4    180.00
Cold Coffee         2    120.00
Veg Biryani         1    280.00
--------------------------------
Sub Total                900.00
Service Charge 5%         45.00
CGST 2.5%                 23.63
SGST 2.5%                 23.63
--------------------------------
Grand Total              992.26
--------------------------------
Cash                    1000.00
Change                     7.74
Thank you! Visit again
`,
    expect: {
      merchant: "SPICE GARDEN RESTAURANT",
      occurredAt: "2026-07-25",
      currency: "INR",
      total: 99226,
      balances: true,
      itemCount: 4,
      tax: 4726,
      serviceCharge: 4500,
    },
  },
  {
    name: "grocery-qty-rate-amount-columns",
    currency: "INR",
    text: `
FRESH MART SUPERMARKET
Shop 4, Sector 18
GST No 27AAAAA0000A1Z0
Date 12/06/2026
Description        Qty   Rate   Amount
Basmati Rice 5 kg    1  450.00  450.00
Toor Dal             2   95.50  191.00
Amul Milk 1L         3   68.00  204.00
Sunflower Oil        1  185.00  185.00
Britannia Bread      2   45.00   90.00
Total Qty: 9
Sub Total                       1120.00
Discount                          50.00
CGST                              26.25
SGST                              26.25
Grand Total                     1122.50
Paid by UPI
`,
    expect: {
      merchant: "FRESH MART SUPERMARKET",
      occurredAt: "2026-06-12",
      total: 112250,
      balances: true,
      itemCount: 5,
      discount: -5000,
      tax: 5250,
    },
  },
  {
    name: "cafe-with-tip-usd",
    currency: "USD",
    text: `
THE CORNER CAFE
Date: 03/04/2026
Flat White             $4.50
Almond Croissant       $3.75
Avocado Toast          $9.00
Subtotal              $17.25
Tax                    $1.55
Tip                    $3.45
Total                 $22.25
Visa ****4412
`,
    expect: {
      merchant: "THE CORNER CAFE",
      occurredAt: "2026-04-03",
      currency: "USD",
      total: 2225,
      balances: true,
      itemCount: 3,
      tax: 155,
      tip: 345,
    },
  },
  {
    name: "kirana-x-quantity-notation",
    currency: "INR",
    text: `
SHREE BALAJI STORES
25-07-2026
2 x Maggi Noodles        28.00
1 x Tata Salt            26.00
3 x Parle-G Biscuit      30.00
1.5 kg Onion             45.00
Total                   129.00
`,
    expect: {
      merchant: "SHREE BALAJI STORES",
      occurredAt: "2026-07-25",
      total: 12900,
      balances: true,
      itemCount: 4,
    },
  },
  {
    name: "round-off-adjustment",
    currency: "INR",
    text: `
QUICK BITE
Date 01/07/2026
Masala Dosa            120.00
Filter Coffee           40.00
Sub Total              160.00
CGST 2.5%                4.00
SGST 2.5%                4.00
Round Off                0.60
Grand Total            168.60
`,
    expect: {
      total: 16860,
      balances: true,
      tax: 800,
    },
  },
  {
    name: "no-total-printed-derives-from-subtotal",
    currency: "INR",
    text: `
STREET FOOD CORNER
Pav Bhaji               90.00
Vada Pav                30.00
Sub Total              120.00
`,
    expect: {
      total: 12000,
      balances: true,
      itemCount: 2,
    },
  },
  {
    // Dutch, because the app ships nl — decimal commas and localised labels are
    // a real case for us, not a hypothetical.
    name: "european-decimal-comma-dutch",
    currency: "EUR",
    text: `
CAFE AMSTERDAM
Datum 14-05-2026
Cappuccino              3,50
Appeltaart              4,20
Mineraalwater           2,30
Subtotaal              10,00
BTW 19%                 1,90
Totaal                 11,90
`,
    expect: {
      currency: "EUR",
      total: 1190,
      balances: true,
      itemCount: 3,
      tax: 190,
    },
  },
  {
    name: "delivery-with-packaging-and-discount",
    currency: "INR",
    text: `
URBAN TIFFIN
Order No: 88213
Date: 20/07/2026
Paneer Roll x2         240.00
Veg Thali               180.00
Item Total              420.00
Packaging Charge         20.00
Delivery Fee             35.00
Discount                 60.00
GST                      22.75
Grand Total             437.75
`,
    expect: {
      total: 43775,
      balances: true,
      serviceCharge: 5500,
      discount: -6000,
      tax: 2275,
    },
  },
  {
    name: "noisy-ocr-artifacts",
    currency: "INR",
    text: `
~~~~ HOTEL SANGAM ~~~~
Ph: 080-4455 6677
FSSAI 12345678901234
Date : 18/07/2026
================================
Chicken Biryani     1    340.00
Raita               1     60.00
================================
Sub Total                400.00
Service Charge            40.00
CGST 2.5%                 11.00
SGST 2.5%                 11.00
================================
TOTAL                    462.00
================================
Payment Mode : Card
Customer Copy
`,
    expect: {
      occurredAt: "2026-07-18",
      total: 46200,
      balances: true,
      itemCount: 2,
      serviceCharge: 4000,
      tax: 2200,
    },
  },
  {
    name: "mismatch-must-not-silently-balance",
    currency: "INR",
    text: `
BROKEN PRINT CAFE
Date 10/07/2026
Sandwich               150.00
Juice                   80.00
Grand Total            300.00
`,
    expect: {
      total: 30000,
      balances: false,
      itemCount: 2,
    },
  },
];
