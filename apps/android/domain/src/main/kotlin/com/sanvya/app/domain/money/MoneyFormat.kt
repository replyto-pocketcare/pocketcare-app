package com.sanvya.app.domain.money

import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

// GENERATED FILE — do not hand-edit.
// Source: packages/core/money/src/index.ts (CURRENCY_LOCALES, format)
// Regenerate with: node tools/parity/generate-money-format.mjs

/**
 * The locale whose conventions each currency is normally written in.
 *
 * Grouping is the reason this exists: INR written in `en_US` is 100,000 but in
 * `en_IN` it is 1,00,000, and every South-Asian currency behaves the same way.
 * Mirrors `CURRENCY_LOCALES` in packages/core/money.
 */
val CURRENCY_LOCALES: Map<String, String> = mapOf(
    "AED" to "ar_AE",
    "AFN" to "fa_AF",
    "ALL" to "sq_AL",
    "AMD" to "hy_AM",
    "ANG" to "nl_CW",
    "AOA" to "pt_AO",
    "ARS" to "es_AR",
    "AUD" to "en_AU",
    "AWG" to "nl_AW",
    "AZN" to "az_AZ",
    "BAM" to "bs_BA",
    "BBD" to "en_BB",
    "BDT" to "bn_BD",
    "BGN" to "bg_BG",
    "BHD" to "ar_BH",
    "BIF" to "fr_BI",
    "BMD" to "en_BM",
    "BND" to "ms_BN",
    "BOB" to "es_BO",
    "BRL" to "pt_BR",
    "BSD" to "en_BS",
    "BTN" to "dz_BT",
    "BWP" to "en_BW",
    "BYN" to "be_BY",
    "BZD" to "en_BZ",
    "CAD" to "en_CA",
    "CDF" to "fr_CD",
    "CHF" to "de_CH",
    "CLP" to "es_CL",
    "CNY" to "zh_CN",
    "COP" to "es_CO",
    "CRC" to "es_CR",
    "CUP" to "es_CU",
    "CVE" to "pt_CV",
    "CZK" to "cs_CZ",
    "DJF" to "fr_DJ",
    "DKK" to "da_DK",
    "DOP" to "es_DO",
    "DZD" to "ar_DZ",
    "EGP" to "ar_EG",
    "ERN" to "ti_ER",
    "ETB" to "am_ET",
    "EUR" to "de_DE",
    "FJD" to "en_FJ",
    "FKP" to "en_FK",
    "FOK" to "en_FO",
    "GBP" to "en_GB",
    "GEL" to "ka_GE",
    "GGP" to "en_GG",
    "GHS" to "en_GH",
    "GIP" to "en_GI",
    "GMD" to "en_GM",
    "GNF" to "fr_GN",
    "GTQ" to "es_GT",
    "GYD" to "en_GY",
    "HKD" to "zh_HK",
    "HNL" to "es_HN",
    "HRK" to "hr_HR",
    "HTG" to "fr_HT",
    "HUF" to "hu_HU",
    "IDR" to "id_ID",
    "ILS" to "he_IL",
    "IMP" to "en_IM",
    "INR" to "en_IN",
    "IQD" to "ar_IQ",
    "IRR" to "fa_IR",
    "ISK" to "is_IS",
    "JEP" to "en_JE",
    "JMD" to "en_JM",
    "JOD" to "ar_JO",
    "JPY" to "ja_JP",
    "KES" to "en_KE",
    "KGS" to "ky_KG",
    "KHR" to "km_KH",
    "KID" to "en_KI",
    "KMF" to "fr_KM",
    "KRW" to "ko_KR",
    "KWD" to "ar_KW",
    "KYD" to "en_KY",
    "KZT" to "kk_KZ",
    "LAK" to "lo_LA",
    "LBP" to "ar_LB",
    "LKR" to "si_LK",
    "LRD" to "en_LR",
    "LSL" to "st_LS",
    "LYD" to "ar_LY",
    "MAD" to "ar_MA",
    "MDL" to "ro_MD",
    "MGA" to "mg_MG",
    "MKD" to "mk_MK",
    "MMK" to "my_MM",
    "MNT" to "mn_MN",
    "MOP" to "zh_MO",
    "MRU" to "ar_MR",
    "MUR" to "en_MU",
    "MVR" to "dv_MV",
    "MWK" to "en_MW",
    "MXN" to "es_MX",
    "MYR" to "ms_MY",
    "MZN" to "pt_MZ",
    "NAD" to "en_NA",
    "NGN" to "en_NG",
    "NIO" to "es_NI",
    "NOK" to "no_NO",
    "NPR" to "ne_NP",
    "NZD" to "en_NZ",
    "OMR" to "ar_OM",
    "PAB" to "es_PA",
    "PEN" to "es_PE",
    "PGK" to "en_PG",
    "PHP" to "en_PH",
    "PKR" to "ur_PK",
    "PLN" to "pl_PL",
    "PYG" to "es_PY",
    "QAR" to "ar_QA",
    "RON" to "ro_RO",
    "RSD" to "sr_RS",
    "RUB" to "ru_RU",
    "RWF" to "rw_RW",
    "SAR" to "ar_SA",
    "SBD" to "en_SB",
    "SCR" to "en_SC",
    "SDG" to "ar_SD",
    "SEK" to "sv_SE",
    "SGD" to "en_SG",
    "SHP" to "en_SH",
    "SLE" to "en_SL",
    "SLL" to "en_SL",
    "SOS" to "so_SO",
    "SRD" to "nl_SR",
    "SSP" to "en_SS",
    "STN" to "pt_ST",
    "SYP" to "ar_SY",
    "SZL" to "en_SZ",
    "THB" to "th_TH",
    "TJS" to "tg_TJ",
    "TMT" to "tk_TM",
    "TND" to "ar_TND",
    "TOP" to "to_TO",
    "TRY" to "tr_TR",
    "TTD" to "en_TT",
    "TVD" to "en_TV",
    "TWD" to "zh_TW",
    "TZS" to "sw_TZ",
    "UAH" to "uk_UA",
    "UGX" to "en_UG",
    "USD" to "en_US",
    "UYU" to "es_UY",
    "UZS" to "uz_UZ",
    "VES" to "es_VE",
    "VND" to "vi_VN",
    "VUV" to "en_VU",
    "WST" to "sm_WS",
    "XAF" to "fr_CM",
    "XCD" to "en_AG",
    "XOF" to "fr_SN",
    "XPF" to "fr_PF",
    "YER" to "ar_YE",
    "ZAR" to "en_ZA",
    "ZMW" to "en_ZM",
    "ZWL" to "en_ZW",
)

private fun localeOf(tag: String): Locale {
    val parts = tag.split("_")
    return if (parts.size >= 2) Locale(parts[0], parts[1]) else Locale(parts[0])
}

/**
 * Format a [Money] for display.
 *
 * Mirrors `format(m, locale)` in packages/core/money, including its quirk: an
 * explicit "en" or "en-US" is IGNORED in favour of the currency's own locale,
 * because those two are the defaults callers pass without meaning to choose,
 * and honouring them would silently break INR grouping everywhere.
 *
 * Fraction digits come from [minorUnits] — never a hardcoded 2. JPY has none
 * and BHD has three.
 */
fun format(m: Money, locale: String? = null): String {
    val tag = if (locale != null && locale != "en" && locale != "en-US" && locale != "en_US") {
        locale.replace("-", "_")
    } else {
        CURRENCY_LOCALES[m.currency] ?: "en_US"
    }

    val digits = minorUnits(m.currency)
    val formatter = NumberFormat.getCurrencyInstance(localeOf(tag)).apply {
        try {
            currency = Currency.getInstance(m.currency)
        } catch (_: IllegalArgumentException) {
            // Not a JDK-known ISO code — the locale's own currency symbol is a
            // better fallback than throwing in the middle of rendering a list.
        }
        minimumFractionDigits = digits
        maximumFractionDigits = digits
    }
    return formatter.format(BigDecimal.valueOf(m.amount).movePointLeft(digits))
}
