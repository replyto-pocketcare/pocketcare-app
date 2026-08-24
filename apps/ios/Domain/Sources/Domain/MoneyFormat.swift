import Foundation

// GENERATED FILE — do not hand-edit.
// Source: packages/core/money/src/index.ts (CURRENCY_LOCALES, format)
// Regenerate with: node tools/parity/generate-money-format.mjs

/**
 The locale whose conventions each currency is normally written in.

 Grouping is the reason this exists: INR written in `en_US` is 100,000 but in
 `en_IN` it is 1,00,000, and every South-Asian currency behaves the same way.
 Mirrors `CURRENCY_LOCALES` in packages/core/money.
 */
public let currencyLocales: [String: String] = [
    "AED": "ar_AE",
    "AFN": "fa_AF",
    "ALL": "sq_AL",
    "AMD": "hy_AM",
    "ANG": "nl_CW",
    "AOA": "pt_AO",
    "ARS": "es_AR",
    "AUD": "en_AU",
    "AWG": "nl_AW",
    "AZN": "az_AZ",
    "BAM": "bs_BA",
    "BBD": "en_BB",
    "BDT": "bn_BD",
    "BGN": "bg_BG",
    "BHD": "ar_BH",
    "BIF": "fr_BI",
    "BMD": "en_BM",
    "BND": "ms_BN",
    "BOB": "es_BO",
    "BRL": "pt_BR",
    "BSD": "en_BS",
    "BTN": "dz_BT",
    "BWP": "en_BW",
    "BYN": "be_BY",
    "BZD": "en_BZ",
    "CAD": "en_CA",
    "CDF": "fr_CD",
    "CHF": "de_CH",
    "CLP": "es_CL",
    "CNY": "zh_CN",
    "COP": "es_CO",
    "CRC": "es_CR",
    "CUP": "es_CU",
    "CVE": "pt_CV",
    "CZK": "cs_CZ",
    "DJF": "fr_DJ",
    "DKK": "da_DK",
    "DOP": "es_DO",
    "DZD": "ar_DZ",
    "EGP": "ar_EG",
    "ERN": "ti_ER",
    "ETB": "am_ET",
    "EUR": "de_DE",
    "FJD": "en_FJ",
    "FKP": "en_FK",
    "FOK": "en_FO",
    "GBP": "en_GB",
    "GEL": "ka_GE",
    "GGP": "en_GG",
    "GHS": "en_GH",
    "GIP": "en_GI",
    "GMD": "en_GM",
    "GNF": "fr_GN",
    "GTQ": "es_GT",
    "GYD": "en_GY",
    "HKD": "zh_HK",
    "HNL": "es_HN",
    "HRK": "hr_HR",
    "HTG": "fr_HT",
    "HUF": "hu_HU",
    "IDR": "id_ID",
    "ILS": "he_IL",
    "IMP": "en_IM",
    "INR": "en_IN",
    "IQD": "ar_IQ",
    "IRR": "fa_IR",
    "ISK": "is_IS",
    "JEP": "en_JE",
    "JMD": "en_JM",
    "JOD": "ar_JO",
    "JPY": "ja_JP",
    "KES": "en_KE",
    "KGS": "ky_KG",
    "KHR": "km_KH",
    "KID": "en_KI",
    "KMF": "fr_KM",
    "KRW": "ko_KR",
    "KWD": "ar_KW",
    "KYD": "en_KY",
    "KZT": "kk_KZ",
    "LAK": "lo_LA",
    "LBP": "ar_LB",
    "LKR": "si_LK",
    "LRD": "en_LR",
    "LSL": "st_LS",
    "LYD": "ar_LY",
    "MAD": "ar_MA",
    "MDL": "ro_MD",
    "MGA": "mg_MG",
    "MKD": "mk_MK",
    "MMK": "my_MM",
    "MNT": "mn_MN",
    "MOP": "zh_MO",
    "MRU": "ar_MR",
    "MUR": "en_MU",
    "MVR": "dv_MV",
    "MWK": "en_MW",
    "MXN": "es_MX",
    "MYR": "ms_MY",
    "MZN": "pt_MZ",
    "NAD": "en_NA",
    "NGN": "en_NG",
    "NIO": "es_NI",
    "NOK": "no_NO",
    "NPR": "ne_NP",
    "NZD": "en_NZ",
    "OMR": "ar_OM",
    "PAB": "es_PA",
    "PEN": "es_PE",
    "PGK": "en_PG",
    "PHP": "en_PH",
    "PKR": "ur_PK",
    "PLN": "pl_PL",
    "PYG": "es_PY",
    "QAR": "ar_QA",
    "RON": "ro_RO",
    "RSD": "sr_RS",
    "RUB": "ru_RU",
    "RWF": "rw_RW",
    "SAR": "ar_SA",
    "SBD": "en_SB",
    "SCR": "en_SC",
    "SDG": "ar_SD",
    "SEK": "sv_SE",
    "SGD": "en_SG",
    "SHP": "en_SH",
    "SLE": "en_SL",
    "SLL": "en_SL",
    "SOS": "so_SO",
    "SRD": "nl_SR",
    "SSP": "en_SS",
    "STN": "pt_ST",
    "SYP": "ar_SY",
    "SZL": "en_SZ",
    "THB": "th_TH",
    "TJS": "tg_TJ",
    "TMT": "tk_TM",
    "TND": "ar_TND",
    "TOP": "to_TO",
    "TRY": "tr_TR",
    "TTD": "en_TT",
    "TVD": "en_TV",
    "TWD": "zh_TW",
    "TZS": "sw_TZ",
    "UAH": "uk_UA",
    "UGX": "en_UG",
    "USD": "en_US",
    "UYU": "es_UY",
    "UZS": "uz_UZ",
    "VES": "es_VE",
    "VND": "vi_VN",
    "VUV": "en_VU",
    "WST": "sm_WS",
    "XAF": "fr_CM",
    "XCD": "en_AG",
    "XOF": "fr_SN",
    "XPF": "fr_PF",
    "YER": "ar_YE",
    "ZAR": "en_ZA",
    "ZMW": "en_ZM",
    "ZWL": "en_ZW",
]

/**
 Format a `Money` for display.

 Mirrors `format(m, locale)` in packages/core/money, including its quirk: an
 explicit "en" or "en-US" is IGNORED in favour of the currency's own locale,
 because those two are the defaults callers pass without meaning to choose,
 and honouring them would silently break INR grouping everywhere.

 Fraction digits come from `minorUnits(currency)` — never a hardcoded 2. JPY
 has none and BHD has three.
 */
public func format(_ m: Money, locale: String? = nil) -> String {
    let tag: String
    if let locale, locale != "en", locale != "en-US", locale != "en_US" {
        tag = locale.replacingOccurrences(of: "-", with: "_")
    } else {
        tag = currencyLocales[m.currency] ?? "en_US"
    }

    let digits = minorUnits(m.currency)
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = m.currency
    formatter.locale = Locale(identifier: tag)
    formatter.minimumFractionDigits = digits
    formatter.maximumFractionDigits = digits

    let major = NSDecimalNumber(value: m.amount)
        .multiplying(byPowerOf10: Int16(-digits))
    return formatter.string(from: major) ?? "\(m.currency) \(major)"
}
