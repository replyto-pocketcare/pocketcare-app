import Foundation

// GENERATED FILE — do not hand-edit.
// Source: packages/core/i18n/src/locales/**
// Regenerate with: node tools/parity/generate-i18n.mjs

/**
 Typed access to every translated string, grouped by the same namespace web
 uses. `S.Transactions.item(n: "2")` is the native equivalent of web's
 `useTranslation("transactions")` + `t("item", { n: 2 })`, and unlike a bare
 `String(localized:)` it stops compiling the moment a key is renamed or an
 interpolation argument is added.

 Non-plural arguments are typed `String`, not `CVarArg`, and the call site
 stringifies. They are emitted as `%@`, which `String(format:)` reads as an
 OBJECT POINTER: an `Int` passed there prints a garbage address instead of a
 number, silently, at runtime. Twelve call sites were doing exactly that before
 the parameter type was tightened — "3 minutes ago" among them.
 */
public enum S {
    public enum Accounts {
        public static var accountName: String { String(localized: "accounts:accountName", table: "Localizable") }
        public static var acrossCurrencies: String { String(localized: "accounts:acrossCurrencies", table: "Localizable") }
        public static var allowNeg: String { String(localized: "accounts:allowNeg", table: "Localizable") }
        public static var allowNegOff: String { String(localized: "accounts:allowNegOff", table: "Localizable") }
        public static var allowNegOn: String { String(localized: "accounts:allowNegOn", table: "Localizable") }
        public static func amountDue(currency: String) -> String {
            String(format: String(localized: "accounts:amountDue", table: "Localizable"), currency)
        }
        public static func approx(amount: String) -> String {
            String(format: String(localized: "accounts:approx", table: "Localizable"), amount)
        }
        public static var archivedTag: String { String(localized: "accounts:archivedTag", table: "Localizable") }
        public static var balAlready: String { String(localized: "accounts:balAlready", table: "Localizable") }
        public static var balanceHeading: String { String(localized: "accounts:balanceHeading", table: "Localizable") }
        public static func balUpdated(amount: String) -> String {
            String(format: String(localized: "accounts:balUpdated", table: "Localizable"), amount)
        }
        public static var cancel: String { String(localized: "accounts:cancel", table: "Localizable") }
        public static var changeDirectly: String { String(localized: "accounts:changeDirectly", table: "Localizable") }
        public static var colour: String { String(localized: "accounts:colour", table: "Localizable") }
        public static func convertedNote(base: String) -> String {
            String(format: String(localized: "accounts:convertedNote", table: "Localizable"), base)
        }
        public static var creditCardDetails: String { String(localized: "accounts:creditCardDetails", table: "Localizable") }
        public static func creditLimit(currency: String) -> String {
            String(format: String(localized: "accounts:creditLimit", table: "Localizable"), currency)
        }
        public static var currency: String { String(localized: "accounts:currency", table: "Localizable") }
        public static var currentBalance: String { String(localized: "accounts:currentBalance", table: "Localizable") }
        public static var delete: String { String(localized: "accounts:delete", table: "Localizable") }
        public static var deleteAll: String { String(localized: "accounts:deleteAll", table: "Localizable") }
        public static var deleteBody: String { String(localized: "accounts:deleteBody", table: "Localizable") }
        public static var deleteKeep: String { String(localized: "accounts:deleteKeep", table: "Localizable") }
        public static var deleteTitle: String { String(localized: "accounts:deleteTitle", table: "Localizable") }
        public static var dematNote: String { String(localized: "accounts:dematNote", table: "Localizable") }
        public static var directNote: String { String(localized: "accounts:directNote", table: "Localizable") }
        public static var dueDay: String { String(localized: "accounts:dueDay", table: "Localizable") }
        public static func dueNextCycle(amount: String, date: String) -> String {
            String(format: String(localized: "accounts:dueNextCycle", table: "Localizable"), amount, date)
        }
        public static func dueThisCycle(amount: String, date: String) -> String {
            String(format: String(localized: "accounts:dueThisCycle", table: "Localizable"), amount, date)
        }
        public static var edit: String { String(localized: "accounts:edit", table: "Localizable") }
        public static var editTitle: String { String(localized: "accounts:editTitle", table: "Localizable") }
        public static var hideArchived: String { String(localized: "accounts:hideArchived", table: "Localizable") }
        public static var includeNw: String { String(localized: "accounts:includeNw", table: "Localizable") }
        public static var includeShort: String { String(localized: "accounts:includeShort", table: "Localizable") }
        public static var inNetWorth: String { String(localized: "accounts:inNetWorth", table: "Localizable") }
        public static func invested(currency: String) -> String {
            String(format: String(localized: "accounts:invested", table: "Localizable"), currency)
        }
        public static var loading: String { String(localized: "accounts:loading", table: "Localizable") }
        public static var newAccount: String { String(localized: "accounts:newAccount", table: "Localizable") }
        public static var newBalance: String { String(localized: "accounts:newBalance", table: "Localizable") }
        public static var newTitle: String { String(localized: "accounts:newTitle", table: "Localizable") }
        public static var noAccounts: String { String(localized: "accounts:noAccounts", table: "Localizable") }
        public static var noBankLink: String { String(localized: "accounts:noBankLink", table: "Localizable") }
        public static func openingBalance(currency: String) -> String {
            String(format: String(localized: "accounts:openingBalance", table: "Localizable"), currency)
        }
        public static var recordAsTxn: String { String(localized: "accounts:recordAsTxn", table: "Localizable") }
        public static var save: String { String(localized: "accounts:save", table: "Localizable") }
        public static var saveChanges: String { String(localized: "accounts:saveChanges", table: "Localizable") }
        public static var saving: String { String(localized: "accounts:saving", table: "Localizable") }
        public static func showArchived(count: String) -> String {
            String(format: String(localized: "accounts:showArchived", table: "Localizable"), count)
        }
        public static var statementDay: String { String(localized: "accounts:statementDay", table: "Localizable") }
        public static var title: String { String(localized: "accounts:title", table: "Localizable") }
        public static func totalCurrencies(total: String, count: String) -> String {
            String(format: String(localized: "accounts:totalCurrencies", table: "Localizable"), total, count)
        }
        public static var txnNote: String { String(localized: "accounts:txnNote", table: "Localizable") }
        public static var typeCash: String { String(localized: "accounts:type.cash", table: "Localizable") }
        public static var typeCreditCard: String { String(localized: "accounts:type.credit_card", table: "Localizable") }
        public static var typeCurrent: String { String(localized: "accounts:type.current", table: "Localizable") }
        public static var typeDemat: String { String(localized: "accounts:type.demat", table: "Localizable") }
        public static var typeMutualFunds: String { String(localized: "accounts:type.mutual_funds", table: "Localizable") }
        public static var typeSavings: String { String(localized: "accounts:type.savings", table: "Localizable") }
        public static var typeStocks: String { String(localized: "accounts:type.stocks", table: "Localizable") }
        public static var typeLabel: String { String(localized: "accounts:typeLabel", table: "Localizable") }
        public static var unarchive: String { String(localized: "accounts:unarchive", table: "Localizable") }
        public static var updateBalance: String { String(localized: "accounts:updateBalance", table: "Localizable") }
    }

    public enum Assistant {
        public static var chats: String { String(localized: "assistant:chats", table: "Localizable") }
        public static var composerPlaceholder: String { String(localized: "assistant:composerPlaceholder", table: "Localizable") }
        public static var confirm: String { String(localized: "assistant:confirm", table: "Localizable") }
        public static var confirmAction: String { String(localized: "assistant:confirmAction", table: "Localizable") }
        public static var continueConversation: String { String(localized: "assistant:continueConversation", table: "Localizable") }
        public static func creditsSuffix(n: String) -> String {
            String(format: String(localized: "assistant:creditsSuffix", table: "Localizable"), n)
        }
        public static var deleteChatAria: String { String(localized: "assistant:deleteChatAria", table: "Localizable") }
        public static var deleteChatMsg: String { String(localized: "assistant:deleteChatMsg", table: "Localizable") }
        public static var deleteChatTitle: String { String(localized: "assistant:deleteChatTitle", table: "Localizable") }
        public static var errDefault: String { String(localized: "assistant:errDefault", table: "Localizable") }
        public static func errGeneric(err: String) -> String {
            String(format: String(localized: "assistant:errGeneric", table: "Localizable"), err)
        }
        public static var errModel: String { String(localized: "assistant:errModel", table: "Localizable") }
        public static var errNetwork: String { String(localized: "assistant:errNetwork", table: "Localizable") }
        public static var errNotConfigured: String { String(localized: "assistant:errNotConfigured", table: "Localizable") }
        public static var goPremium: String { String(localized: "assistant:goPremium", table: "Localizable") }
        public static var greeting: String { String(localized: "assistant:greeting", table: "Localizable") }
        public static var help: String { String(localized: "assistant:help", table: "Localizable") }
        public static var landingIntro: String { String(localized: "assistant:landingIntro", table: "Localizable") }
        public static var micDenied: String { String(localized: "assistant:micDenied", table: "Localizable") }
        public static var micHint: String { String(localized: "assistant:micHint", table: "Localizable") }
        public static var micSpeak: String { String(localized: "assistant:micSpeak", table: "Localizable") }
        public static var micStop: String { String(localized: "assistant:micStop", table: "Localizable") }
        public static var micTranscribing: String { String(localized: "assistant:micTranscribing", table: "Localizable") }
        public static var newChat: String { String(localized: "assistant:newChat", table: "Localizable") }
        public static var noChats: String { String(localized: "assistant:noChats", table: "Localizable") }
        public static var opening: String { String(localized: "assistant:opening", table: "Localizable") }
        public static var outFreeBold: String { String(localized: "assistant:outFreeBold", table: "Localizable") }
        public static var outFreeRest: String { String(localized: "assistant:outFreeRest", table: "Localizable") }
        public static var outPaidBold: String { String(localized: "assistant:outPaidBold", table: "Localizable") }
        public static var outPaidRest: String { String(localized: "assistant:outPaidRest", table: "Localizable") }
        public static func paymentFailed(msg: String) -> String {
            String(format: String(localized: "assistant:paymentFailed", table: "Localizable"), msg)
        }
        public static var premiumBody: String { String(localized: "assistant:premiumBody", table: "Localizable") }
        public static var premiumFeature: String { String(localized: "assistant:premiumFeature", table: "Localizable") }
        public static var privacyBody: String { String(localized: "assistant:privacyBody", table: "Localizable") }
        public static var privacyTitle: String { String(localized: "assistant:privacyTitle", table: "Localizable") }
        public static var queries: String { String(localized: "assistant:queries", table: "Localizable") }
        public static func quotaResets(date: String) -> String {
            String(format: String(localized: "assistant:quotaResets", table: "Localizable"), date)
        }
        public static var seePlans: String { String(localized: "assistant:seePlans", table: "Localizable") }
        public static var sendAria: String { String(localized: "assistant:sendAria", table: "Localizable") }
        public static var skip: String { String(localized: "assistant:skip", table: "Localizable") }
        public static var startChat: String { String(localized: "assistant:startChat", table: "Localizable") }
        public static var suggestions: [String] {
            [
                String(localized: "assistant:suggestions.1", table: "Localizable"),
                String(localized: "assistant:suggestions.2", table: "Localizable"),
                String(localized: "assistant:suggestions.3", table: "Localizable"),
                String(localized: "assistant:suggestions.4", table: "Localizable"),
                String(localized: "assistant:suggestions.5", table: "Localizable"),
                String(localized: "assistant:suggestions.6", table: "Localizable"),
                String(localized: "assistant:suggestions.7", table: "Localizable"),
            ]
        }
        public static var thinking: String { String(localized: "assistant:thinking", table: "Localizable") }
        public static var title: String { String(localized: "assistant:title", table: "Localizable") }
        public static var understand: String { String(localized: "assistant:understand", table: "Localizable") }
        public static var untitledChat: String { String(localized: "assistant:untitledChat", table: "Localizable") }
        public static var viewData: String { String(localized: "assistant:viewData", table: "Localizable") }
    }

    public enum Budgets {
        public static var addBudget: String { String(localized: "budgets:addBudget", table: "Localizable") }
        public static var addCategories: String { String(localized: "budgets:addCategories", table: "Localizable") }
        public static var alertAt: String { String(localized: "budgets:alertAt", table: "Localizable") }
        public static var alertMeAt: String { String(localized: "budgets:alertMeAt", table: "Localizable") }
        public static var allSpending: String { String(localized: "budgets:allSpending", table: "Localizable") }
        public static var cancel: String { String(localized: "budgets:cancel", table: "Localizable") }
        public static var categoriesEmpty: String { String(localized: "budgets:categoriesEmpty", table: "Localizable") }
        public static var categoriesOptional: String { String(localized: "budgets:categoriesOptional", table: "Localizable") }
        public static var createFirst: String { String(localized: "budgets:createFirst", table: "Localizable") }
        public static var customDates: String { String(localized: "budgets:customDates", table: "Localizable") }
        public static var deleteBudgetAria: String { String(localized: "budgets:deleteBudgetAria", table: "Localizable") }
        public static func deleteMsg(title: String) -> String {
            String(format: String(localized: "budgets:deleteMsg", table: "Localizable"), title)
        }
        public static var deleteTitle: String { String(localized: "budgets:deleteTitle", table: "Localizable") }
        public static var edit: String { String(localized: "budgets:edit", table: "Localizable") }
        public static var errDates: String { String(localized: "budgets:errDates", table: "Localizable") }
        public static var errLimit: String { String(localized: "budgets:errLimit", table: "Localizable") }
        public static var labels: String { String(localized: "budgets:labels", table: "Localizable") }
        public static var labelsOptional: String { String(localized: "budgets:labelsOptional", table: "Localizable") }
        public static func left(amount: String) -> String {
            String(format: String(localized: "budgets:left", table: "Localizable"), amount)
        }
        public static func limit(currency: String) -> String {
            String(format: String(localized: "budgets:limit", table: "Localizable"), currency)
        }
        public static var limitShort: String { String(localized: "budgets:limitShort", table: "Localizable") }
        public static var nameOptional: String { String(localized: "budgets:nameOptional", table: "Localizable") }
        public static var namePlaceholder: String { String(localized: "budgets:namePlaceholder", table: "Localizable") }
        public static var newBudget: String { String(localized: "budgets:newBudget", table: "Localizable") }
        public static var noBudgetsBody: String { String(localized: "budgets:noBudgetsBody", table: "Localizable") }
        public static var noBudgetsTitle: String { String(localized: "budgets:noBudgetsTitle", table: "Localizable") }
        public static func over(amount: String) -> String {
            String(format: String(localized: "budgets:over", table: "Localizable"), amount)
        }
        public static var percentOfLimit: String { String(localized: "budgets:percentOfLimit", table: "Localizable") }
        public static var periodDaily: String { String(localized: "budgets:period.daily", table: "Localizable") }
        public static var periodMonthly: String { String(localized: "budgets:period.monthly", table: "Localizable") }
        public static var periodWeekly: String { String(localized: "budgets:period.weekly", table: "Localizable") }
        public static var periodYearly: String { String(localized: "budgets:period.yearly", table: "Localizable") }
        public static var recurring: String { String(localized: "budgets:recurring", table: "Localizable") }
        public static var save: String { String(localized: "budgets:save", table: "Localizable") }
        public static func spent(amount: String) -> String {
            String(format: String(localized: "budgets:spent", table: "Localizable"), amount)
        }
        public static var timeframe: String { String(localized: "budgets:timeframe", table: "Localizable") }
        public static var title: String { String(localized: "budgets:title", table: "Localizable") }
    }

    public enum Cards {
        public static var addCard: String { String(localized: "cards:addCard", table: "Localizable") }
        public static var amountDue: String { String(localized: "cards:amountDue", table: "Localizable") }
        public static var amountPlaceholder: String { String(localized: "cards:amountPlaceholder", table: "Localizable") }
        public static func availableCredit(amount: String) -> String {
            String(format: String(localized: "cards:availableCredit", table: "Localizable"), amount)
        }
        public static var cancel: String { String(localized: "cards:cancel", table: "Localizable") }
        public static var cardHolder: String { String(localized: "cards:cardHolder", table: "Localizable") }
        public static var cardNumber: String { String(localized: "cards:cardNumber", table: "Localizable") }
        public static var cardNumberPlaceholder: String { String(localized: "cards:cardNumberPlaceholder", table: "Localizable") }
        public static var clickToManage: String { String(localized: "cards:clickToManage", table: "Localizable") }
        public static var creditLimit: String { String(localized: "cards:creditLimit", table: "Localizable") }
        public static var dueDay: String { String(localized: "cards:dueDay", table: "Localizable") }
        public static func dueNextCycle(amount: String) -> String {
            String(format: String(localized: "cards:dueNextCycle", table: "Localizable"), amount)
        }
        public static var dueThisCycle: String { String(localized: "cards:dueThisCycle", table: "Localizable") }
        public static var editDetails: String { String(localized: "cards:editDetails", table: "Localizable") }
        public static func emiCoveredBody(count: Int) -> String {
            String(format: String(localized: "cards:emiCoveredBody", defaultValue: "", table: "Localizable"), count)
        }
        public static var emiCoveredConfirm: String { String(localized: "cards:emiCoveredConfirm", table: "Localizable") }
        public static var emiCoveredSkip: String { String(localized: "cards:emiCoveredSkip", table: "Localizable") }
        public static var emiCoveredTitle: String { String(localized: "cards:emiCoveredTitle", table: "Localizable") }
        public static func emiNo(n: String) -> String {
            String(format: String(localized: "cards:emiNo", table: "Localizable"), n)
        }
        public static var emptyBody: String { String(localized: "cards:emptyBody", table: "Localizable") }
        public static var newAccount: String { String(localized: "cards:newAccount", table: "Localizable") }
        public static func newSpendThisCycle(amount: String) -> String {
            String(format: String(localized: "cards:newSpendThisCycle", table: "Localizable"), amount)
        }
        public static func ofLimit(limit: String) -> String {
            String(format: String(localized: "cards:ofLimit", table: "Localizable"), limit)
        }
        public static var payBy: String { String(localized: "cards:payBy", table: "Localizable") }
        public static var save: String { String(localized: "cards:save", table: "Localizable") }
        public static var settle: String { String(localized: "cards:settle", table: "Localizable") }
        public static var settleFrom: String { String(localized: "cards:settleFrom", table: "Localizable") }
        public static var spentThisCycle: String { String(localized: "cards:spentThisCycle", table: "Localizable") }
        public static func statement(date: String) -> String {
            String(format: String(localized: "cards:statement", table: "Localizable"), date)
        }
        public static var statementDay: String { String(localized: "cards:statementDay", table: "Localizable") }
        public static var subtitle: String { String(localized: "cards:subtitle", table: "Localizable") }
        public static var title: String { String(localized: "cards:title", table: "Localizable") }
        public static var wallet: String { String(localized: "cards:wallet", table: "Localizable") }
    }

    public enum Cashflow {
        public static func actions(name: String) -> String {
            String(format: String(localized: "cashflow:actions", table: "Localizable"), name)
        }
        public static var add: String { String(localized: "cashflow:add", table: "Localizable") }
        public static var addIncome: String { String(localized: "cashflow:addIncome", table: "Localizable") }
        public static var addIncomeTitle: String { String(localized: "cashflow:addIncomeTitle", table: "Localizable") }
        public static var addPayment: String { String(localized: "cashflow:addPayment", table: "Localizable") }
        public static var addPaymentTitle: String { String(localized: "cashflow:addPaymentTitle", table: "Localizable") }
        public static var addRecurringSaving: String { String(localized: "cashflow:addRecurringSaving", table: "Localizable") }
        public static var addSavingsTitle: String { String(localized: "cashflow:addSavingsTitle", table: "Localizable") }
        public static var amount: String { String(localized: "cashflow:amount", table: "Localizable") }
        public static func amountCur(base: String) -> String {
            String(format: String(localized: "cashflow:amountCur", table: "Localizable"), base)
        }
        public static var autoPosts: String { String(localized: "cashflow:autoPosts", table: "Localizable") }
        public static var cancel: String { String(localized: "cashflow:cancel", table: "Localizable") }
        public static var categoryOptional: String { String(localized: "cashflow:categoryOptional", table: "Localizable") }
        public static func commitments(count: String) -> String {
            String(format: String(localized: "cashflow:commitments", table: "Localizable"), count)
        }
        public static var confirm: String { String(localized: "cashflow:confirm", table: "Localizable") }
        public static var depositInto: String { String(localized: "cashflow:depositInto", table: "Localizable") }
        public static var dirLabelIncome: String { String(localized: "cashflow:dirLabel.income", table: "Localizable") }
        public static var dirLabelPayment: String { String(localized: "cashflow:dirLabel.payment", table: "Localizable") }
        public static var edit: String { String(localized: "cashflow:edit", table: "Localizable") }
        public static var emiPerMonth: String { String(localized: "cashflow:emiPerMonth", table: "Localizable") }
        public static var emptyIncomes: String { String(localized: "cashflow:emptyIncomes", table: "Localizable") }
        public static var emptyPayments: String { String(localized: "cashflow:emptyPayments", table: "Localizable") }
        public static var emptySavings: String { String(localized: "cashflow:emptySavings", table: "Localizable") }
        public static var financialSummary: String { String(localized: "cashflow:financialSummary", table: "Localizable") }
        public static var firstDue: String { String(localized: "cashflow:firstDue", table: "Localizable") }
        public static var freeSurplus: String { String(localized: "cashflow:freeSurplus", table: "Localizable") }
        public static var freqDaily: String { String(localized: "cashflow:freq.daily", table: "Localizable") }
        public static var freqMonthly: String { String(localized: "cashflow:freq.monthly", table: "Localizable") }
        public static var freqWeekly: String { String(localized: "cashflow:freq.weekly", table: "Localizable") }
        public static var freqYearly: String { String(localized: "cashflow:freq.yearly", table: "Localizable") }
        public static var frequency: String { String(localized: "cashflow:frequency", table: "Localizable") }
        public static var goToLoans: String { String(localized: "cashflow:goToLoans", table: "Localizable") }
        public static var incomeMinusPayments: String { String(localized: "cashflow:incomeMinusPayments", table: "Localizable") }
        public static var incomeVsPayments: String { String(localized: "cashflow:incomeVsPayments", table: "Localizable") }
        public static var intoSavings: String { String(localized: "cashflow:intoSavings", table: "Localizable") }
        public static var intro: String { String(localized: "cashflow:intro", table: "Localizable") }
        public static var loanFallback: String { String(localized: "cashflow:loanFallback", table: "Localizable") }
        public static var loanNote: String { String(localized: "cashflow:loanNote", table: "Localizable") }
        public static func loanSubtitle(amount: String) -> String {
            String(format: String(localized: "cashflow:loanSubtitle", table: "Localizable"), amount)
        }
        public static var makeRecurring: String { String(localized: "cashflow:makeRecurring", table: "Localizable") }
        public static func modalAdd(what: String) -> String {
            String(format: String(localized: "cashflow:modalAdd", table: "Localizable"), what)
        }
        public static func modalEdit(what: String) -> String {
            String(format: String(localized: "cashflow:modalEdit", table: "Localizable"), what)
        }
        public static var name: String { String(localized: "cashflow:name", table: "Localizable") }
        public static var netDifference: String { String(localized: "cashflow:netDifference", table: "Localizable") }
        public static var netMonthly: String { String(localized: "cashflow:netMonthly", table: "Localizable") }
        public static func next(date: String) -> String {
            String(format: String(localized: "cashflow:next", table: "Localizable"), date)
        }
        public static var nextDue: String { String(localized: "cashflow:nextDue", table: "Localizable") }
        public static var nextExpected: String { String(localized: "cashflow:nextExpected", table: "Localizable") }
        public static var noCategory: String { String(localized: "cashflow:noCategory", table: "Localizable") }
        public static var oneOff: String { String(localized: "cashflow:oneOff", table: "Localizable") }
        public static var payFrom: String { String(localized: "cashflow:payFrom", table: "Localizable") }
        public static var payments: String { String(localized: "cashflow:payments", table: "Localizable") }
        public static func per(unit: String) -> String {
            String(format: String(localized: "cashflow:per", table: "Localizable"), unit)
        }
        public static func perAnnum(pct: String) -> String {
            String(format: String(localized: "cashflow:perAnnum", table: "Localizable"), pct)
        }
        public static var perMonth: String { String(localized: "cashflow:perMonth", table: "Localizable") }
        public static var plannedPayments: String { String(localized: "cashflow:plannedPayments", table: "Localizable") }
        public static var plannedPaymentsTitle: String { String(localized: "cashflow:plannedPaymentsTitle", table: "Localizable") }
        public static func plans(count: String) -> String {
            String(format: String(localized: "cashflow:plans", table: "Localizable"), count)
        }
        public static func portfolioMeta(count: Int, amount: String) -> String {
            String(format: String(localized: "cashflow:portfolioMeta", defaultValue: "", table: "Localizable"), count, amount)
        }
        public static var portfolioTitle: String { String(localized: "cashflow:portfolioTitle", table: "Localizable") }
        public static var postAuto: String { String(localized: "cashflow:postAuto", table: "Localizable") }
        public static var postAutoOff: String { String(localized: "cashflow:postAutoOff", table: "Localizable") }
        public static var projNote: String { String(localized: "cashflow:projNote", table: "Localizable") }
        public static var quickAdd: String { String(localized: "cashflow:quickAdd", table: "Localizable") }
        public static var quickAddNoteLink: String { String(localized: "cashflow:quickAddNoteLink", table: "Localizable") }
        public static var quickAddNotePost: String { String(localized: "cashflow:quickAddNotePost", table: "Localizable") }
        public static var quickAddNotePre: String { String(localized: "cashflow:quickAddNotePre", table: "Localizable") }
        public static var recurringIncome: String { String(localized: "cashflow:recurringIncome", table: "Localizable") }
        public static var recurringIncomes: String { String(localized: "cashflow:recurringIncomes", table: "Localizable") }
        public static var remove: String { String(localized: "cashflow:remove", table: "Localizable") }
        public static func removeItemMsg(name: String) -> String {
            String(format: String(localized: "cashflow:removeItemMsg", table: "Localizable"), name)
        }
        public static var removeItemTitle: String { String(localized: "cashflow:removeItemTitle", table: "Localizable") }
        public static func removeLoanMsg(name: String) -> String {
            String(format: String(localized: "cashflow:removeLoanMsg", table: "Localizable"), name)
        }
        public static var removeLoanTitle: String { String(localized: "cashflow:removeLoanTitle", table: "Localizable") }
        public static func removeRecurringMsg(name: String) -> String {
            String(format: String(localized: "cashflow:removeRecurringMsg", table: "Localizable"), name)
        }
        public static var removeRecurringTitle: String { String(localized: "cashflow:removeRecurringTitle", table: "Localizable") }
        public static func removeSubMsg(name: String) -> String {
            String(format: String(localized: "cashflow:removeSubMsg", table: "Localizable"), name)
        }
        public static var removeSubTitle: String { String(localized: "cashflow:removeSubTitle", table: "Localizable") }
        public static var returnPa: String { String(localized: "cashflow:returnPa", table: "Localizable") }
        public static var returnPct: String { String(localized: "cashflow:returnPct", table: "Localizable") }
        public static var save: String { String(localized: "cashflow:save", table: "Localizable") }
        public static var savingEllipsis: String { String(localized: "cashflow:savingEllipsis", table: "Localizable") }
        public static var savingsInvest: String { String(localized: "cashflow:savingsInvest", table: "Localizable") }
        public static var selectAccount: String { String(localized: "cashflow:selectAccount", table: "Localizable") }
        public static func spentSoFar(amount: String, date: String) -> String {
            String(format: String(localized: "cashflow:spentSoFar", table: "Localizable"), amount, date)
        }
        public static func spentTooltip(count: String, date: String) -> String {
            String(format: String(localized: "cashflow:spentTooltip", table: "Localizable"), count, date)
        }
        public static var startedRenewal: String { String(localized: "cashflow:startedRenewal", table: "Localizable") }
        public static var subscription: String { String(localized: "cashflow:subscription", table: "Localizable") }
        public static var timeframeNounDaily: String { String(localized: "cashflow:timeframeNoun.daily", table: "Localizable") }
        public static var timeframeNounMonthly: String { String(localized: "cashflow:timeframeNoun.monthly", table: "Localizable") }
        public static var timeframeNounWeekly: String { String(localized: "cashflow:timeframeNoun.weekly", table: "Localizable") }
        public static var timeframeNounYearly: String { String(localized: "cashflow:timeframeNoun.yearly", table: "Localizable") }
        public static var title: String { String(localized: "cashflow:title", table: "Localizable") }
        public static var trackHoldingsLink: String { String(localized: "cashflow:trackHoldingsLink", table: "Localizable") }
        public static var trackHoldingsPost: String { String(localized: "cashflow:trackHoldingsPost", table: "Localizable") }
        public static var trackHoldingsPre: String { String(localized: "cashflow:trackHoldingsPre", table: "Localizable") }
        public static var viewSchedule: String { String(localized: "cashflow:viewSchedule", table: "Localizable") }
        public static var whereIncomeGoes: String { String(localized: "cashflow:whereIncomeGoes", table: "Localizable") }
    }

    public enum Categories {
        public static var add: String { String(localized: "categories:add", table: "Localizable") }
        public static var backToSettings: String { String(localized: "categories:backToSettings", table: "Localizable") }
        public static var cancel: String { String(localized: "categories:cancel", table: "Localizable") }
        public static var collapse: String { String(localized: "categories:collapse", table: "Localizable") }
        public static func deleteMsg(name: String) -> String {
            String(format: String(localized: "categories:deleteMsg", table: "Localizable"), name)
        }
        public static var deleteTitle: String { String(localized: "categories:deleteTitle", table: "Localizable") }
        public static var edit: String { String(localized: "categories:edit", table: "Localizable") }
        public static var expand: String { String(localized: "categories:expand", table: "Localizable") }
        public static var expense: String { String(localized: "categories:expense", table: "Localizable") }
        public static var income: String { String(localized: "categories:income", table: "Localizable") }
        public static var kindExpense: String { String(localized: "categories:kind.expense", table: "Localizable") }
        public static var kindIncome: String { String(localized: "categories:kind.income", table: "Localizable") }
        public static var name: String { String(localized: "categories:name", table: "Localizable") }
        public static var newCategory: String { String(localized: "categories:newCategory", table: "Localizable") }
        public static var save: String { String(localized: "categories:save", table: "Localizable") }
        public static var searchPlaceholder: String { String(localized: "categories:searchPlaceholder", table: "Localizable") }
        public static var title: String { String(localized: "categories:title", table: "Localizable") }
        public static var topLevel: String { String(localized: "categories:topLevel", table: "Localizable") }
        public static func under(name: String) -> String {
            String(format: String(localized: "categories:under", table: "Localizable"), name)
        }
    }

    public enum Dashboard {
        public static var addWidget: String { String(localized: "dashboard:addWidget", table: "Localizable") }
        public static var addWidgetIntro: String { String(localized: "dashboard:addWidgetIntro", table: "Localizable") }
        public static var allAdded: String { String(localized: "dashboard:allAdded", table: "Localizable") }
        public static var customize: String { String(localized: "dashboard:customize", table: "Localizable") }
        public static var efShort: String { String(localized: "dashboard:efShort", table: "Localizable") }
        public static var emptyBody: String { String(localized: "dashboard:emptyBody", table: "Localizable") }
        public static var emptyBudgets: String { String(localized: "dashboard:emptyBudgets", table: "Localizable") }
        public static var emptyCashflow: String { String(localized: "dashboard:emptyCashflow", table: "Localizable") }
        public static var emptyGoals: String { String(localized: "dashboard:emptyGoals", table: "Localizable") }
        public static var emptyLabels: String { String(localized: "dashboard:emptyLabels", table: "Localizable") }
        public static var emptyRecent: String { String(localized: "dashboard:emptyRecent", table: "Localizable") }
        public static var emptySpending: String { String(localized: "dashboard:emptySpending", table: "Localizable") }
        public static var emptySplits: String { String(localized: "dashboard:emptySplits", table: "Localizable") }
        public static var emptySubscriptions: String { String(localized: "dashboard:emptySubscriptions", table: "Localizable") }
        public static var emptyTitle: String { String(localized: "dashboard:emptyTitle", table: "Localizable") }
        public static var emptyUpcoming: String { String(localized: "dashboard:emptyUpcoming", table: "Localizable") }
        public static var inflow: String { String(localized: "dashboard:inflow", table: "Localizable") }
        public static var lastMonth: String { String(localized: "dashboard:lastMonth", table: "Localizable") }
        public static func moreCategories(count: String) -> String {
            String(format: String(localized: "dashboard:moreCategories", table: "Localizable"), count)
        }
        public static func moreItems(count: String) -> String {
            String(format: String(localized: "dashboard:moreItems", table: "Localizable"), count)
        }
        public static var moveDown: String { String(localized: "dashboard:moveDown", table: "Localizable") }
        public static var moveUp: String { String(localized: "dashboard:moveUp", table: "Localizable") }
        public static var net: String { String(localized: "dashboard:net", table: "Localizable") }
        public static var outflow: String { String(localized: "dashboard:outflow", table: "Localizable") }
        public static var perMonth: String { String(localized: "dashboard:perMonth", table: "Localizable") }
        public static var premium: String { String(localized: "dashboard:premium", table: "Localizable") }
        public static var premiumNote: String { String(localized: "dashboard:premiumNote", table: "Localizable") }
        public static func singleCurrency(base: String) -> String {
            String(format: String(localized: "dashboard:singleCurrency", table: "Localizable"), base)
        }
        public static func spent(amount: String) -> String {
            String(format: String(localized: "dashboard:spent", table: "Localizable"), amount)
        }
        public static func subsCount(count: Int) -> String {
            String(format: String(localized: "dashboard:subsCount", defaultValue: "", table: "Localizable"), count)
        }
        public static func subsCountSpent(count: Int, amount: String) -> String {
            String(format: String(localized: "dashboard:subsCountSpent", defaultValue: "", table: "Localizable"), count, amount)
        }
        public static var subsSpentNote: String { String(localized: "dashboard:subsSpentNote", table: "Localizable") }
        public static var thisMonth: String { String(localized: "dashboard:thisMonth", table: "Localizable") }
        public static var tileBudgets: String { String(localized: "dashboard:tile.budgets", table: "Localizable") }
        public static var tileByCategory: String { String(localized: "dashboard:tile.byCategory", table: "Localizable") }
        public static var tileByLabel: String { String(localized: "dashboard:tile.byLabel", table: "Localizable") }
        public static var tileCashflow: String { String(localized: "dashboard:tile.cashflow", table: "Localizable") }
        public static var tileCurrencies: String { String(localized: "dashboard:tile.currencies", table: "Localizable") }
        public static var tileGoals: String { String(localized: "dashboard:tile.goals", table: "Localizable") }
        public static var tileMonthCompare: String { String(localized: "dashboard:tile.monthCompare", table: "Localizable") }
        public static var tileNetTrend: String { String(localized: "dashboard:tile.netTrend", table: "Localizable") }
        public static var tileRecent: String { String(localized: "dashboard:tile.recent", table: "Localizable") }
        public static var tileSpending: String { String(localized: "dashboard:tile.spending", table: "Localizable") }
        public static var tileSplits: String { String(localized: "dashboard:tile.splits", table: "Localizable") }
        public static var tileSubscriptions: String { String(localized: "dashboard:tile.subscriptions", table: "Localizable") }
        public static var tileTrends: String { String(localized: "dashboard:tile.trends", table: "Localizable") }
        public static var tileUpcoming: String { String(localized: "dashboard:tile.upcoming", table: "Localizable") }
        public static var trendLast1m: String { String(localized: "dashboard:trendLast1m", table: "Localizable") }
        public static var trendLast1w: String { String(localized: "dashboard:trendLast1w", table: "Localizable") }
        public static var trendLast1y: String { String(localized: "dashboard:trendLast1y", table: "Localizable") }
        public static var trendLast3d: String { String(localized: "dashboard:trendLast3d", table: "Localizable") }
        public static var width: String { String(localized: "dashboard:width", table: "Localizable") }
        public static var youAreOwed: String { String(localized: "dashboard:youAreOwed", table: "Localizable") }
        public static var youOwe: String { String(localized: "dashboard:youOwe", table: "Localizable") }
    }

    public enum Data {
        public static var backToSettings: String { String(localized: "data:backToSettings", table: "Localizable") }
        public static var csvFile: String { String(localized: "data:csvFile", table: "Localizable") }
        public static var export: String { String(localized: "data:export", table: "Localizable") }
        public static var exportBtn: String { String(localized: "data:exportBtn", table: "Localizable") }
        public static func exported(count: Int) -> String {
            String(format: String(localized: "data:exported", defaultValue: "", table: "Localizable"), count)
        }
        public static func exportFailed(msg: String) -> String {
            String(format: String(localized: "data:exportFailed", table: "Localizable"), msg)
        }
        public static var exportNote: String { String(localized: "data:exportNote", table: "Localizable") }
        public static var fileFormat: String { String(localized: "data:fileFormat", table: "Localizable") }
        public static func firstIssues(issues: String) -> String {
            String(format: String(localized: "data:firstIssues", table: "Localizable"), issues)
        }
        public static var footerNote: String { String(localized: "data:footerNote", table: "Localizable") }
        public static func foundPreview(count: Int, file: String) -> String {
            String(format: String(localized: "data:foundPreview", defaultValue: "", table: "Localizable"), count, file)
        }
        public static var `import`: String { String(localized: "data:import", table: "Localizable") }
        public static func importBtn(count: Int) -> String {
            String(format: String(localized: "data:importBtn", defaultValue: "", table: "Localizable"), count)
        }
        public static var importing: String { String(localized: "data:importing", table: "Localizable") }
        public static var introPre: String { String(localized: "data:introPre", table: "Localizable") }
        public static var noExport: String { String(localized: "data:noExport", table: "Localizable") }
        public static var noRows: String { String(localized: "data:noRows", table: "Localizable") }
        public static var preparing: String { String(localized: "data:preparing", table: "Localizable") }
        public static func readFail(msg: String) -> String {
            String(format: String(localized: "data:readFail", table: "Localizable"), msg)
        }
        public static func resultLine(created: String, skipped: String, failed: String) -> String {
            String(format: String(localized: "data:resultLine", table: "Localizable"), created, skipped, failed)
        }
        public static var skipDup: String { String(localized: "data:skipDup", table: "Localizable") }
        public static var thAccount: String { String(localized: "data:thAccount", table: "Localizable") }
        public static var thAmount: String { String(localized: "data:thAmount", table: "Localizable") }
        public static var thCategory: String { String(localized: "data:thCategory", table: "Localizable") }
        public static var thDate: String { String(localized: "data:thDate", table: "Localizable") }
        public static var thType: String { String(localized: "data:thType", table: "Localizable") }
        public static var title: String { String(localized: "data:title", table: "Localizable") }
        public static var trialNote: String { String(localized: "data:trialNote", table: "Localizable") }
    }

    public enum Feedback {
        public static var areaAccountsCards: String { String(localized: "feedback:areaAccountsCards", table: "Localizable") }
        public static var areaAskSanvya: String { String(localized: "feedback:areaAskSanvya", table: "Localizable") }
        public static var areaBudgets: String { String(localized: "feedback:areaBudgets", table: "Localizable") }
        public static var areaDashboard: String { String(localized: "feedback:areaDashboard", table: "Localizable") }
        public static var areaFriendsSplits: String { String(localized: "feedback:areaFriendsSplits", table: "Localizable") }
        public static var areaGoals: String { String(localized: "feedback:areaGoals", table: "Localizable") }
        public static var areaInsights: String { String(localized: "feedback:areaInsights", table: "Localizable") }
        public static var areaInvestments: String { String(localized: "feedback:areaInvestments", table: "Localizable") }
        public static var areaLabel: String { String(localized: "feedback:areaLabel", table: "Localizable") }
        public static var areaLoans: String { String(localized: "feedback:areaLoans", table: "Localizable") }
        public static var areaOther: String { String(localized: "feedback:areaOther", table: "Localizable") }
        public static var areaPlaceholder: String { String(localized: "feedback:areaPlaceholder", table: "Localizable") }
        public static var areaSettingsBilling: String { String(localized: "feedback:areaSettingsBilling", table: "Localizable") }
        public static var areaSubscriptions: String { String(localized: "feedback:areaSubscriptions", table: "Localizable") }
        public static var areaSyncOffline: String { String(localized: "feedback:areaSyncOffline", table: "Localizable") }
        public static var areaTransactions: String { String(localized: "feedback:areaTransactions", table: "Localizable") }
        public static var autoIncluded: String { String(localized: "feedback:autoIncluded", table: "Localizable") }
        public static var bugPlaceholder: String { String(localized: "feedback:bugPlaceholder", table: "Localizable") }
        public static var cancel: String { String(localized: "feedback:cancel", table: "Localizable") }
        public static var done: String { String(localized: "feedback:done", table: "Localizable") }
        public static var errNeedBug: String { String(localized: "feedback:errNeedBug", table: "Localizable") }
        public static var errNeedSuggestion: String { String(localized: "feedback:errNeedSuggestion", table: "Localizable") }
        public static var errSubmit: String { String(localized: "feedback:errSubmit", table: "Localizable") }
        public static var includeLog: String { String(localized: "feedback:includeLog", table: "Localizable") }
        public static var includeLogHint: String { String(localized: "feedback:includeLogHint", table: "Localizable") }
        public static var intro: String { String(localized: "feedback:intro", table: "Localizable") }
        public static var kindBug: String { String(localized: "feedback:kindBug", table: "Localizable") }
        public static var kindSuggestion: String { String(localized: "feedback:kindSuggestion", table: "Localizable") }
        public static var sendAnother: String { String(localized: "feedback:sendAnother", table: "Localizable") }
        public static var sendBug: String { String(localized: "feedback:sendBug", table: "Localizable") }
        public static var sending: String { String(localized: "feedback:sending", table: "Localizable") }
        public static var sendSuggestion: String { String(localized: "feedback:sendSuggestion", table: "Localizable") }
        public static var severityLabel: String { String(localized: "feedback:severityLabel", table: "Localizable") }
        public static var sevFatal: String { String(localized: "feedback:sevFatal", table: "Localizable") }
        public static var sevHigh: String { String(localized: "feedback:sevHigh", table: "Localizable") }
        public static var sevLow: String { String(localized: "feedback:sevLow", table: "Localizable") }
        public static var sevMedium: String { String(localized: "feedback:sevMedium", table: "Localizable") }
        public static var suggestionPlaceholder: String { String(localized: "feedback:suggestionPlaceholder", table: "Localizable") }
        public static var thanksBug: String { String(localized: "feedback:thanksBug", table: "Localizable") }
        public static var thanksBugBody: String { String(localized: "feedback:thanksBugBody", table: "Localizable") }
        public static var thanksSuggestion: String { String(localized: "feedback:thanksSuggestion", table: "Localizable") }
        public static var thanksSuggestionBody: String { String(localized: "feedback:thanksSuggestionBody", table: "Localizable") }
        public static var title: String { String(localized: "feedback:title", table: "Localizable") }
        public static var titlePlaceholder: String { String(localized: "feedback:titlePlaceholder", table: "Localizable") }
    }

    public enum Goals {
        public static var add: String { String(localized: "goals:add", table: "Localizable") }
        public static var addFunds: String { String(localized: "goals:addFunds", table: "Localizable") }
        public static var addGoal: String { String(localized: "goals:addGoal", table: "Localizable") }
        public static var addSavingsFirst: String { String(localized: "goals:addSavingsFirst", table: "Localizable") }
        public static func amount(currency: String) -> String {
            String(format: String(localized: "goals:amount", table: "Localizable"), currency)
        }
        public static var block: String { String(localized: "goals:block", table: "Localizable") }
        public static var blockFunds: String { String(localized: "goals:blockFunds", table: "Localizable") }
        public static var cancel: String { String(localized: "goals:cancel", table: "Localizable") }
        public static var delete: String { String(localized: "goals:delete", table: "Localizable") }
        public static func deleteMsg(name: String) -> String {
            String(format: String(localized: "goals:deleteMsg", table: "Localizable"), name)
        }
        public static var deleteTitle: String { String(localized: "goals:deleteTitle", table: "Localizable") }
        public static var edit: String { String(localized: "goals:edit", table: "Localizable") }
        public static var efCheckbox: String { String(localized: "goals:efCheckbox", table: "Localizable") }
        public static var efFirst: String { String(localized: "goals:efFirst", table: "Localizable") }
        public static var efLiquid: String { String(localized: "goals:efLiquid", table: "Localizable") }
        public static var errName: String { String(localized: "goals:errName", table: "Localizable") }
        public static var errTarget: String { String(localized: "goals:errTarget", table: "Localizable") }
        public static var fromAccount: String { String(localized: "goals:fromAccount", table: "Localizable") }
        public static var funded: String { String(localized: "goals:funded", table: "Localizable") }
        public static func goalActions(name: String) -> String {
            String(format: String(localized: "goals:goalActions", table: "Localizable"), name)
        }
        public static var goalName: String { String(localized: "goals:goalName", table: "Localizable") }
        public static var goalReached: String { String(localized: "goals:goalReached", table: "Localizable") }
        public static func leftToTarget(amount: String) -> String {
            String(format: String(localized: "goals:leftToTarget", table: "Localizable"), amount)
        }
        public static var lockedUntil: String { String(localized: "goals:lockedUntil", table: "Localizable") }
        public static var newGoal: String { String(localized: "goals:newGoal", table: "Localizable") }
        public static var noGoals: String { String(localized: "goals:noGoals", table: "Localizable") }
        public static var save: String { String(localized: "goals:save", table: "Localizable") }
        public static func target(currency: String) -> String {
            String(format: String(localized: "goals:target", table: "Localizable"), currency)
        }
        public static var title: String { String(localized: "goals:title", table: "Localizable") }
        public static var willCap: String { String(localized: "goals:willCap", table: "Localizable") }
    }

    public enum Groups {
        public static func added(name: String) -> String {
            String(format: String(localized: "groups:added", table: "Localizable"), name)
        }
        public static var addExistingFriends: String { String(localized: "groups:addExistingFriends", table: "Localizable") }
        public static func alreadyIn(name: String) -> String {
            String(format: String(localized: "groups:alreadyIn", table: "Localizable"), name)
        }
        public static func autoSplitCreate(kind: String) -> String {
            String(format: String(localized: "groups:autoSplitCreate", table: "Localizable"), kind)
        }
        public static var autoSplitDates: String { String(localized: "groups:autoSplitDates", table: "Localizable") }
        public static func autoSplitDesc(start: String, end: String, kind: String) -> String {
            String(format: String(localized: "groups:autoSplitDesc", table: "Localizable"), start, end, kind)
        }
        public static var autoSplitLabel: String { String(localized: "groups:autoSplitLabel", table: "Localizable") }
        public static var autoSplitOn: String { String(localized: "groups:autoSplitOn", table: "Localizable") }
        public static var autoSplitTag: String { String(localized: "groups:autoSplitTag", table: "Localizable") }
        public static var backToGroups: String { String(localized: "groups:backToGroups", table: "Localizable") }
        public static var backToGroupsLink: String { String(localized: "groups:backToGroupsLink", table: "Localizable") }
        public static var cancel: String { String(localized: "groups:cancel", table: "Localizable") }
        public static var copied: String { String(localized: "groups:copied", table: "Localizable") }
        public static var copyLink: String { String(localized: "groups:copyLink", table: "Localizable") }
        public static var create: String { String(localized: "groups:create", table: "Localizable") }
        public static var createFirst: String { String(localized: "groups:createFirst", table: "Localizable") }
        public static var creating: String { String(localized: "groups:creating", table: "Localizable") }
        public static var datesOptional: String { String(localized: "groups:datesOptional", table: "Localizable") }
        public static var delete: String { String(localized: "groups:delete", table: "Localizable") }
        public static func deleteMsg(name: String) -> String {
            String(format: String(localized: "groups:deleteMsg", table: "Localizable"), name)
        }
        public static var deleteTitle: String { String(localized: "groups:deleteTitle", table: "Localizable") }
        public static var edit: String { String(localized: "groups:edit", table: "Localizable") }
        public static func editKind(kind: String) -> String {
            String(format: String(localized: "groups:editKind", table: "Localizable"), kind)
        }
        public static var emailPlaceholder: String { String(localized: "groups:emailPlaceholder", table: "Localizable") }
        public static func error(msg: String) -> String {
            String(format: String(localized: "groups:error", table: "Localizable"), msg)
        }
        public static var expenseFallback: String { String(localized: "groups:expenseFallback", table: "Localizable") }
        public static var expensesTitle: String { String(localized: "groups:expensesTitle", table: "Localizable") }
        public static var friends: String { String(localized: "groups:friends", table: "Localizable") }
        public static var groupActions: String { String(localized: "groups:groupActions", table: "Localizable") }
        public static var groupNamePlaceholder: String { String(localized: "groups:groupNamePlaceholder", table: "Localizable") }
        public static var groupNotFound: String { String(localized: "groups:groupNotFound", table: "Localizable") }
        public static var invite: String { String(localized: "groups:invite", table: "Localizable") }
        public static func inviteAddEmail(email: String) -> String {
            String(format: String(localized: "groups:inviteAddEmail", table: "Localizable"), email)
        }
        public static var inviteBody: String { String(localized: "groups:inviteBody", table: "Localizable") }
        public static func inviteCount(count: Int) -> String {
            String(format: String(localized: "groups:inviteCount", defaultValue: "", table: "Localizable"), count)
        }
        public static func invitedAdded(count: Int) -> String {
            String(format: String(localized: "groups:invitedAdded", defaultValue: "", table: "Localizable"), count)
        }
        public static func invitedFailed(names: String) -> String {
            String(format: String(localized: "groups:invitedFailed", table: "Localizable"), names)
        }
        public static func invitedLinks(count: Int) -> String {
            String(format: String(localized: "groups:invitedLinks", defaultValue: "", table: "Localizable"), count)
        }
        public static func inviteNarrow(count: Int) -> String {
            String(format: String(localized: "groups:inviteNarrow", defaultValue: "", table: "Localizable"), count)
        }
        public static var invitePlaceholder: String { String(localized: "groups:invitePlaceholder", table: "Localizable") }
        public static func inviteTo(name: String) -> String {
            String(format: String(localized: "groups:inviteTo", table: "Localizable"), name)
        }
        public static var kindGroup: String { String(localized: "groups:kind.group", table: "Localizable") }
        public static var kindTrip: String { String(localized: "groups:kind.trip", table: "Localizable") }
        public static func members(count: Int) -> String {
            String(format: String(localized: "groups:members", defaultValue: "", table: "Localizable"), count)
        }
        public static var membersTitle: String { String(localized: "groups:membersTitle", table: "Localizable") }
        public static var namePlaceholder: String { String(localized: "groups:namePlaceholder", table: "Localizable") }
        public static var new: String { String(localized: "groups:new", table: "Localizable") }
        public static var newGroupTrip: String { String(localized: "groups:newGroupTrip", table: "Localizable") }
        public static var noDates: String { String(localized: "groups:noDates", table: "Localizable") }
        public static var noExpensesLink: String { String(localized: "groups:noExpensesLink", table: "Localizable") }
        public static func noExpensesPost(kind: String) -> String {
            String(format: String(localized: "groups:noExpensesPost", table: "Localizable"), kind)
        }
        public static var noExpensesPre: String { String(localized: "groups:noExpensesPre", table: "Localizable") }
        public static var noGroupsBody: String { String(localized: "groups:noGroupsBody", table: "Localizable") }
        public static var noGroupsTitle: String { String(localized: "groups:noGroupsTitle", table: "Localizable") }
        public static var orShareLink: String { String(localized: "groups:orShareLink", table: "Localizable") }
        public static func owesYouAmt(amount: String) -> String {
            String(format: String(localized: "groups:owesYouAmt", table: "Localizable"), amount)
        }
        public static var remove: String { String(localized: "groups:remove", table: "Localizable") }
        public static var save: String { String(localized: "groups:save", table: "Localizable") }
        public static func settledBetween(from: String, to: String) -> String {
            String(format: String(localized: "groups:settledBetween", table: "Localizable"), from, to)
        }
        public static func settledPaidYou(name: String) -> String {
            String(format: String(localized: "groups:settledPaidYou", table: "Localizable"), name)
        }
        public static var settledPending: String { String(localized: "groups:settledPending", table: "Localizable") }
        public static var settledTag: String { String(localized: "groups:settledTag", table: "Localizable") }
        public static var settledTitle: String { String(localized: "groups:settledTitle", table: "Localizable") }
        public static func settledYouPaid(name: String) -> String {
            String(format: String(localized: "groups:settledYouPaid", table: "Localizable"), name)
        }
        public static var someone: String { String(localized: "groups:someone", table: "Localizable") }
        public static var title: String { String(localized: "groups:title", table: "Localizable") }
        public static var totalSpent: String { String(localized: "groups:totalSpent", table: "Localizable") }
        public static var tripNamePlaceholder: String { String(localized: "groups:tripNamePlaceholder", table: "Localizable") }
        public static var youOwe: String { String(localized: "groups:youOwe", table: "Localizable") }
        public static func youOweAmt(amount: String) -> String {
            String(format: String(localized: "groups:youOweAmt", table: "Localizable"), amount)
        }
        public static var youreOwed: String { String(localized: "groups:youreOwed", table: "Localizable") }
    }

    public enum Help {
        public static var footer: String { String(localized: "help:footer", table: "Localizable") }
        public static func noMatch(query: String) -> String {
            String(format: String(localized: "help:noMatch", table: "Localizable"), query)
        }
        public static var searchPlaceholder: String { String(localized: "help:searchPlaceholder", table: "Localizable") }
        public static var subtitleLink: String { String(localized: "help:subtitleLink", table: "Localizable") }
        public static var subtitlePost: String { String(localized: "help:subtitlePost", table: "Localizable") }
        public static var subtitlePre: String { String(localized: "help:subtitlePre", table: "Localizable") }
        public static var title: String { String(localized: "help:title", table: "Localizable") }
    }

    public enum Insights {
        public static var feedBody: String { String(localized: "insights:feedBody", table: "Localizable") }
        public static var feedTitle: String { String(localized: "insights:feedTitle", table: "Localizable") }
        public static var goPremium: String { String(localized: "insights:goPremium", table: "Localizable") }
        public static var statements: String { String(localized: "insights:statements", table: "Localizable") }
        public static var title: String { String(localized: "insights:title", table: "Localizable") }
    }

    public enum Investments {
        public static var addBankFirst: String { String(localized: "investments:addBankFirst", table: "Localizable") }
        public static var adding: String { String(localized: "investments:adding", table: "Localizable") }
        public static var addInvAccount: String { String(localized: "investments:addInvAccount", table: "Localizable") }
        public static var addInvestment: String { String(localized: "investments:addInvestment", table: "Localizable") }
        public static func addTo(name: String) -> String {
            String(format: String(localized: "investments:addTo", table: "Localizable"), name)
        }
        public static var allInvestments: String { String(localized: "investments:allInvestments", table: "Localizable") }
        public static var allocation: String { String(localized: "investments:allocation", table: "Localizable") }
        public static var alreadyHold: String { String(localized: "investments:alreadyHold", table: "Localizable") }
        public static func amountInvested(cur: String) -> String {
            String(format: String(localized: "investments:amountInvested", table: "Localizable"), cur)
        }
        public static func asOf(date: String) -> String {
            String(format: String(localized: "investments:asOf", table: "Localizable"), date)
        }
        public static func avgCost(cur: String) -> String {
            String(format: String(localized: "investments:avgCost", table: "Localizable"), cur)
        }
        public static var byExchangeScheme: String { String(localized: "investments:byExchangeScheme", table: "Localizable") }
        public static var cancel: String { String(localized: "investments:cancel", table: "Localizable") }
        public static var currentValue: String { String(localized: "investments:currentValue", table: "Localizable") }
        public static func currentValueCur(cur: String) -> String {
            String(format: String(localized: "investments:currentValueCur", table: "Localizable"), cur)
        }
        public static func currentValueOptional(cur: String) -> String {
            String(format: String(localized: "investments:currentValueOptional", table: "Localizable"), cur)
        }
        public static var debitsFrom: String { String(localized: "investments:debitsFrom", table: "Localizable") }
        public static func deductFrom(amount: String) -> String {
            String(format: String(localized: "investments:deductFrom", table: "Localizable"), amount)
        }
        public static var demat: String { String(localized: "investments:demat", table: "Localizable") }
        public static func dividendsEarned(fy: String) -> String {
            String(format: String(localized: "investments:dividendsEarned", table: "Localizable"), fy)
        }
        public static var dividendsNote: String { String(localized: "investments:dividendsNote", table: "Localizable") }
        public static var edit: String { String(localized: "investments:edit", table: "Localizable") }
        public static func eodNote(asOf: String) -> String {
            String(format: String(localized: "investments:eodNote", table: "Localizable"), asOf)
        }
        public static var existingNote: String { String(localized: "investments:existingNote", table: "Localizable") }
        public static var gainLossByGroup: String { String(localized: "investments:gainLossByGroup", table: "Localizable") }
        public static func holdingsCount(count: Int) -> String {
            String(format: String(localized: "investments:holdingsCount", defaultValue: "", table: "Localizable"), count)
        }
        public static var inOurList: String { String(localized: "investments:inOurList", table: "Localizable") }
        public static var insights: String { String(localized: "investments:insights", table: "Localizable") }
        public static var interestPa: String { String(localized: "investments:interestPa", table: "Localizable") }
        public static var invested: String { String(localized: "investments:invested", table: "Localizable") }
        public static func investedLabel(amount: String) -> String {
            String(format: String(localized: "investments:investedLabel", table: "Localizable"), amount)
        }
        public static var investmentAccount: String { String(localized: "investments:investmentAccount", table: "Localizable") }
        public static var ltpLabel: String { String(localized: "investments:ltpLabel", table: "Localizable") }
        public static var matures: String { String(localized: "investments:matures", table: "Localizable") }
        public static var maturityDate: String { String(localized: "investments:maturityDate", table: "Localizable") }
        public static func nameLabel(type: String) -> String {
            String(format: String(localized: "investments:nameLabel", table: "Localizable"), type)
        }
        public static func navAvgCost(cur: String) -> String {
            String(format: String(localized: "investments:navAvgCost", table: "Localizable"), cur)
        }
        public static func navCost(cur: String) -> String {
            String(format: String(localized: "investments:navCost", table: "Localizable"), cur)
        }
        public static var newFund: String { String(localized: "investments:newFund", table: "Localizable") }
        public static var newOrHold: String { String(localized: "investments:newOrHold", table: "Localizable") }
        public static var nextSipDate: String { String(localized: "investments:nextSipDate", table: "Localizable") }
        public static var noFundAccount: String { String(localized: "investments:noFundAccount", table: "Localizable") }
        public static var noInvAccountBodyPost: String { String(localized: "investments:noInvAccountBodyPost", table: "Localizable") }
        public static var noInvAccountBodyPre: String { String(localized: "investments:noInvAccountBodyPre", table: "Localizable") }
        public static var noInvAccountTitle: String { String(localized: "investments:noInvAccountTitle", table: "Localizable") }
        public static var noInvestments: String { String(localized: "investments:noInvestments", table: "Localizable") }
        public static var notListed: String { String(localized: "investments:notListed", table: "Localizable") }
        public static func overFunds(account: String) -> String {
            String(format: String(localized: "investments:overFunds", table: "Localizable"), account)
        }
        public static func perAnnum(rate: String) -> String {
            String(format: String(localized: "investments:perAnnum", table: "Localizable"), rate)
        }
        public static var qty: String { String(localized: "investments:qty", table: "Localizable") }
        public static var quantity: String { String(localized: "investments:quantity", table: "Localizable") }
        public static var remove: String { String(localized: "investments:remove", table: "Localizable") }
        public static func removeMsg(label: String) -> String {
            String(format: String(localized: "investments:removeMsg", table: "Localizable"), label)
        }
        public static var removeTitle: String { String(localized: "investments:removeTitle", table: "Localizable") }
        public static var save: String { String(localized: "investments:save", table: "Localizable") }
        public static var selectAccount: String { String(localized: "investments:selectAccount", table: "Localizable") }
        public static func sipAmount(cur: String) -> String {
            String(format: String(localized: "investments:sipAmount", table: "Localizable"), cur)
        }
        public static var sipFreqMonthly: String { String(localized: "investments:sipFreq.monthly", table: "Localizable") }
        public static var sipFreqWeekly: String { String(localized: "investments:sipFreq.weekly", table: "Localizable") }
        public static var sipFreqYearly: String { String(localized: "investments:sipFreq.yearly", table: "Localizable") }
        public static func sipNote(amount: String, account: String) -> String {
            String(format: String(localized: "investments:sipNote", table: "Localizable"), amount, account)
        }
        public static var syncNote: String { String(localized: "investments:syncNote", table: "Localizable") }
        public static var theAmount: String { String(localized: "investments:theAmount", table: "Localizable") }
        public static var thisAccount: String { String(localized: "investments:thisAccount", table: "Localizable") }
        public static var title: String { String(localized: "investments:title", table: "Localizable") }
        public static var total: String { String(localized: "investments:total", table: "Localizable") }
        public static var totalGainLoss: String { String(localized: "investments:totalGainLoss", table: "Localizable") }
        public static var units: String { String(localized: "investments:units", table: "Localizable") }
        public static var untracked: String { String(localized: "investments:untracked", table: "Localizable") }
        public static var valueLabel: String { String(localized: "investments:valueLabel", table: "Localizable") }
    }

    public enum Join {
        public static var missingToken: String { String(localized: "join:missingToken", table: "Localizable") }
        public static var needAuth: String { String(localized: "join:needAuth", table: "Localizable") }
        public static var opening: String { String(localized: "join:opening", table: "Localizable") }
        public static var signInCreate: String { String(localized: "join:signInCreate", table: "Localizable") }
        public static var title: String { String(localized: "join:title", table: "Localizable") }
    }

    public enum Labels {
        public static var addLabel: String { String(localized: "labels:addLabel", table: "Localizable") }
        public static var backToSettings: String { String(localized: "labels:backToSettings", table: "Localizable") }
        public static var cancel: String { String(localized: "labels:cancel", table: "Localizable") }
        public static var delete: String { String(localized: "labels:delete", table: "Localizable") }
        public static func deleteMsg(name: String) -> String {
            String(format: String(localized: "labels:deleteMsg", table: "Localizable"), name)
        }
        public static var deleteTitle: String { String(localized: "labels:deleteTitle", table: "Localizable") }
        public static var edit: String { String(localized: "labels:edit", table: "Localizable") }
        public static var newLabel: String { String(localized: "labels:newLabel", table: "Localizable") }
        public static var noLabels: String { String(localized: "labels:noLabels", table: "Localizable") }
        public static var save: String { String(localized: "labels:save", table: "Localizable") }
        public static var searchPlaceholder: String { String(localized: "labels:searchPlaceholder", table: "Localizable") }
        public static var title: String { String(localized: "labels:title", table: "Localizable") }
    }

    public enum Loans {
        public static var active: String { String(localized: "loans:active", table: "Localizable") }
        public static var add: String { String(localized: "loans:add", table: "Localizable") }
        public static var addEmiHint: String { String(localized: "loans:addEmiHint", table: "Localizable") }
        public static var addFirst: String { String(localized: "loans:addFirst", table: "Localizable") }
        public static var addInterestHint: String { String(localized: "loans:addInterestHint", table: "Localizable") }
        public static var addLoan: String { String(localized: "loans:addLoan", table: "Localizable") }
        public static var alsoRecord: String { String(localized: "loans:alsoRecord", table: "Localizable") }
        public static var amortPrincipalOnly: String { String(localized: "loans:amortPrincipalOnly", table: "Localizable") }
        public static var amortTitle: String { String(localized: "loans:amortTitle", table: "Localizable") }
        public static var amortWithInterest: String { String(localized: "loans:amortWithInterest", table: "Localizable") }
        public static func autoCalcEdit(amount: String) -> String {
            String(format: String(localized: "loans:autoCalcEdit", table: "Localizable"), amount)
        }
        public static var autoCalcHint: String { String(localized: "loans:autoCalcHint", table: "Localizable") }
        public static func autoCalcWas(amount: String) -> String {
            String(format: String(localized: "loans:autoCalcWas", table: "Localizable"), amount)
        }
        public static var autoMarked: String { String(localized: "loans:autoMarked", table: "Localizable") }
        public static func autoMarkedTitle(date: String) -> String {
            String(format: String(localized: "loans:autoMarkedTitle", table: "Localizable"), date)
        }
        public static var autoMarkHint: String { String(localized: "loans:autoMarkHint", table: "Localizable") }
        public static var autoMarkLabel: String { String(localized: "loans:autoMarkLabel", table: "Localizable") }
        public static var autoMarkOff: String { String(localized: "loans:autoMarkOff", table: "Localizable") }
        public static var autoMarkOn: String { String(localized: "loans:autoMarkOn", table: "Localizable") }
        public static var autoMarkTitle: String { String(localized: "loans:autoMarkTitle", table: "Localizable") }
        public static var balance: String { String(localized: "loans:balance", table: "Localizable") }
        public static var cancel: String { String(localized: "loans:cancel", table: "Localizable") }
        public static var cardEmisPaid: String { String(localized: "loans:cardEmisPaid", table: "Localizable") }
        public static var cardInterestRate: String { String(localized: "loans:cardInterestRate", table: "Localizable") }
        public static var cardMonthlyEmi: String { String(localized: "loans:cardMonthlyEmi", table: "Localizable") }
        public static var cardPrincipal: String { String(localized: "loans:cardPrincipal", table: "Localizable") }
        public static var cardSuffix: String { String(localized: "loans:cardSuffix", table: "Localizable") }
        public static var chargedTo: String { String(localized: "loans:chargedTo", table: "Localizable") }
        public static var chargedToCardHint: String { String(localized: "loans:chargedToCardHint", table: "Localizable") }
        public static var chargedToHint: String { String(localized: "loans:chargedToHint", table: "Localizable") }
        public static var closed: String { String(localized: "loans:closed", table: "Localizable") }
        public static var currentInterest: String { String(localized: "loans:currentInterest", table: "Localizable") }
        public static var delete: String { String(localized: "loans:delete", table: "Localizable") }
        public static func deleteMsg(name: String) -> String {
            String(format: String(localized: "loans:deleteMsg", table: "Localizable"), name)
        }
        public static var deleteTitle: String { String(localized: "loans:deleteTitle", table: "Localizable") }
        public static var dontRecord: String { String(localized: "loans:dontRecord", table: "Localizable") }
        public static var dueBlankHint: String { String(localized: "loans:dueBlankHint", table: "Localizable") }
        public static func dueDate(date: String) -> String {
            String(format: String(localized: "loans:dueDate", table: "Localizable"), date)
        }
        public static var dueDay: String { String(localized: "loans:dueDay", table: "Localizable") }
        public static func dueLine(date: String) -> String {
            String(format: String(localized: "loans:dueLine", table: "Localizable"), date)
        }
        public static func dueOnEach(ord: String, n: String) -> String {
            String(format: String(localized: "loans:dueOnEach", table: "Localizable"), ord, n)
        }
        public static var edit: String { String(localized: "loans:edit", table: "Localizable") }
        public static var editTitle: String { String(localized: "loans:editTitle", table: "Localizable") }
        public static var emiAmount: String { String(localized: "loans:emiAmount", table: "Localizable") }
        public static func emiPaidCount(paid: String, tenure: String) -> String {
            String(format: String(localized: "loans:emiPaidCount", table: "Localizable"), paid, tenure)
        }
        public static var emiThisMonth: String { String(localized: "loans:emiThisMonth", table: "Localizable") }
        public static var fixed: String { String(localized: "loans:fixed", table: "Localizable") }
        public static var interestAmount: String { String(localized: "loans:interestAmount", table: "Localizable") }
        public static var interestPa: String { String(localized: "loans:interestPa", table: "Localizable") }
        public static var interestType: String { String(localized: "loans:interestType", table: "Localizable") }
        public static var lender: String { String(localized: "loans:lender", table: "Localizable") }
        public static var loading: String { String(localized: "loans:loading", table: "Localizable") }
        public static var loanAmount: String { String(localized: "loans:loanAmount", table: "Localizable") }
        public static func loanCount(count: Int) -> String {
            String(format: String(localized: "loans:loanCount", defaultValue: "", table: "Localizable"), count)
        }
        public static var loanFallback: String { String(localized: "loans:loanFallback", table: "Localizable") }
        public static func markEmiPaid(n: String) -> String {
            String(format: String(localized: "loans:markEmiPaid", table: "Localizable"), n)
        }
        public static var markPaid: String { String(localized: "loans:markPaid", table: "Localizable") }
        public static var markPaidRecord: String { String(localized: "loans:markPaidRecord", table: "Localizable") }
        public static var markPaidTitle: String { String(localized: "loans:markPaidTitle", table: "Localizable") }
        public static func monthlyEmi(cur: String) -> String {
            String(format: String(localized: "loans:monthlyEmi", table: "Localizable"), cur)
        }
        public static var nextEmiDue: String { String(localized: "loans:nextEmiDue", table: "Localizable") }
        public static var noLoansBody: String { String(localized: "loans:noLoansBody", table: "Localizable") }
        public static var noLoansTitle: String { String(localized: "loans:noLoansTitle", table: "Localizable") }
        public static var notExist: String { String(localized: "loans:notExist", table: "Localizable") }
        public static var notLinked: String { String(localized: "loans:notLinked", table: "Localizable") }
        public static func nthEmi(ord: String, n: String) -> String {
            String(format: String(localized: "loans:nthEmi", table: "Localizable"), ord, n)
        }
        public static var off: String { String(localized: "loans:off", table: "Localizable") }
        public static var on: String { String(localized: "loans:on", table: "Localizable") }
        public static func onDate(date: String) -> String {
            String(format: String(localized: "loans:onDate", table: "Localizable"), date)
        }
        public static var paidCheck: String { String(localized: "loans:paidCheck", table: "Localizable") }
        public static func paidCount(paid: String) -> String {
            String(format: String(localized: "loans:paidCount", table: "Localizable"), paid)
        }
        public static var paidOn: String { String(localized: "loans:paidOn", table: "Localizable") }
        public static var paidSoFar: String { String(localized: "loans:paidSoFar", table: "Localizable") }
        public static var paidTitle: String { String(localized: "loans:paidTitle", table: "Localizable") }
        public static func perAnnum(rate: String) -> String {
            String(format: String(localized: "loans:perAnnum", table: "Localizable"), rate)
        }
        public static func postsExpense(amount: String, date: String) -> String {
            String(format: String(localized: "loans:postsExpense", table: "Localizable"), amount, date)
        }
        public static var postsToCard: String { String(localized: "loans:postsToCard", table: "Localizable") }
        public static func principal(cur: String) -> String {
            String(format: String(localized: "loans:principal", table: "Localizable"), cur)
        }
        public static var principalAmount: String { String(localized: "loans:principalAmount", table: "Localizable") }
        public static var rateVariableSuffix: String { String(localized: "loans:rateVariableSuffix", table: "Localizable") }
        public static var remaining: String { String(localized: "loans:remaining", table: "Localizable") }
        public static func remainingEmis(count: String) -> String {
            String(format: String(localized: "loans:remainingEmis", table: "Localizable"), count)
        }
        public static var remembersAccount: String { String(localized: "loans:remembersAccount", table: "Localizable") }
        public static var save: String { String(localized: "loans:save", table: "Localizable") }
        public static var savingEllipsis: String { String(localized: "loans:savingEllipsis", table: "Localizable") }
        public static var startedOn: String { String(localized: "loans:startedOn", table: "Localizable") }
        public static var tenureMonths: String { String(localized: "loans:tenureMonths", table: "Localizable") }
        public static var title: String { String(localized: "loans:title", table: "Localizable") }
        public static var totalEmisMonth: String { String(localized: "loans:totalEmisMonth", table: "Localizable") }
        public static var totalInterestSchedule: String { String(localized: "loans:totalInterestSchedule", table: "Localizable") }
        public static var useIt: String { String(localized: "loans:useIt", table: "Localizable") }
        public static var variable: String { String(localized: "loans:variable", table: "Localizable") }
        public static var variableAddTenure: String { String(localized: "loans:variableAddTenure", table: "Localizable") }
        public static var variableEditNote: String { String(localized: "loans:variableEditNote", table: "Localizable") }
        public static var variableNote: String { String(localized: "loans:variableNote", table: "Localizable") }
        public static var variableNoteBold: String { String(localized: "loans:variableNoteBold", table: "Localizable") }
        public static var variableNotePost: String { String(localized: "loans:variableNotePost", table: "Localizable") }
        public static var variableNotePre: String { String(localized: "loans:variableNotePre", table: "Localizable") }
        public static var variableTitle: String { String(localized: "loans:variableTitle", table: "Localizable") }
        public static var varies: String { String(localized: "loans:varies", table: "Localizable") }
    }

    public enum Login {
        public static var accountCreated: String { String(localized: "login:accountCreated", table: "Localizable") }
        public static var back: String { String(localized: "login:back", table: "Localizable") }
        public static var backToSignin: String { String(localized: "login:backToSignin", table: "Localizable") }
        public static var codePlaceholder: String { String(localized: "login:codePlaceholder", table: "Localizable") }
        public static var confirmNewPw: String { String(localized: "login:confirmNewPw", table: "Localizable") }
        public static var confirmPassword: String { String(localized: "login:confirmPassword", table: "Localizable") }
        public static var `continue`: String { String(localized: "login:continue", table: "Localizable") }
        public static var continueGoogle: String { String(localized: "login:continueGoogle", table: "Localizable") }
        public static var displayName: String { String(localized: "login:displayName", table: "Localizable") }
        public static var emailLabel: String { String(localized: "login:emailLabel", table: "Localizable") }
        public static var emailVerified: String { String(localized: "login:emailVerified", table: "Localizable") }
        public static var encNote: String { String(localized: "login:encNote", table: "Localizable") }
        public static var errEmail: String { String(localized: "login:errEmail", table: "Localizable") }
        public static var errName: String { String(localized: "login:errName", table: "Localizable") }
        public static var errOtp: String { String(localized: "login:errOtp", table: "Localizable") }
        public static var errPwLen: String { String(localized: "login:errPwLen", table: "Localizable") }
        public static var errPwMatch: String { String(localized: "login:errPwMatch", table: "Localizable") }
        public static var errResetEmail: String { String(localized: "login:errResetEmail", table: "Localizable") }
        public static var errSignin: String { String(localized: "login:errSignin", table: "Localizable") }
        public static var forgotPassword: String { String(localized: "login:forgotPassword", table: "Localizable") }
        public static var friendlyExists: String { String(localized: "login:friendlyExists", table: "Localizable") }
        public static var friendlyExpired: String { String(localized: "login:friendlyExpired", table: "Localizable") }
        public static var friendlyInvalidCreds: String { String(localized: "login:friendlyInvalidCreds", table: "Localizable") }
        public static var friendlyNotConfirmed: String { String(localized: "login:friendlyNotConfirmed", table: "Localizable") }
        public static var newCodeSent: String { String(localized: "login:newCodeSent", table: "Localizable") }
        public static var newPw: String { String(localized: "login:newPw", table: "Localizable") }
        public static var newPwTitle: String { String(localized: "login:newPwTitle", table: "Localizable") }
        public static var or: String { String(localized: "login:or", table: "Localizable") }
        public static var passwordPlaceholder: String { String(localized: "login:passwordPlaceholder", table: "Localizable") }
        public static var pwUpdated: String { String(localized: "login:pwUpdated", table: "Localizable") }
        public static var registerSub: String { String(localized: "login:registerSub", table: "Localizable") }
        public static var registerTitle: String { String(localized: "login:registerTitle", table: "Localizable") }
        public static var resend: String { String(localized: "login:resend", table: "Localizable") }
        public static var resetSub: String { String(localized: "login:resetSub", table: "Localizable") }
        public static var resetTitle: String { String(localized: "login:resetTitle", table: "Localizable") }
        public static var saving: String { String(localized: "login:saving", table: "Localizable") }
        public static var sendResetCode: String { String(localized: "login:sendResetCode", table: "Localizable") }
        public static func sentCode(email: String) -> String {
            String(format: String(localized: "login:sentCode", table: "Localizable"), email)
        }
        public static func sentReset(email: String) -> String {
            String(format: String(localized: "login:sentReset", table: "Localizable"), email)
        }
        public static var setNewPwDefault: String { String(localized: "login:setNewPwDefault", table: "Localizable") }
        public static var signedIn: String { String(localized: "login:signedIn", table: "Localizable") }
        public static var signInBtn: String { String(localized: "login:signInBtn", table: "Localizable") }
        public static var signinSub: String { String(localized: "login:signinSub", table: "Localizable") }
        public static var signinTitle: String { String(localized: "login:signinTitle", table: "Localizable") }
        public static var signUpGoogle: String { String(localized: "login:signUpGoogle", table: "Localizable") }
        public static var switchToRegister: String { String(localized: "login:switchToRegister", table: "Localizable") }
        public static var switchToSignin: String { String(localized: "login:switchToSignin", table: "Localizable") }
        public static var updatePw: String { String(localized: "login:updatePw", table: "Localizable") }
        public static var verifyCode: String { String(localized: "login:verifyCode", table: "Localizable") }
        public static var verifyCreate: String { String(localized: "login:verifyCreate", table: "Localizable") }
        public static var verifying: String { String(localized: "login:verifying", table: "Localizable") }
        public static var verifyTitle: String { String(localized: "login:verifyTitle", table: "Localizable") }
    }

    public enum Notifications {
        public static func daysAgo(count: String) -> String {
            String(format: String(localized: "notifications:daysAgo", table: "Localizable"), count)
        }
        public static var dismiss: String { String(localized: "notifications:dismiss", table: "Localizable") }
        public static var emptyBody: String { String(localized: "notifications:emptyBody", table: "Localizable") }
        public static var emptyTitle: String { String(localized: "notifications:emptyTitle", table: "Localizable") }
        public static var enableCta: String { String(localized: "notifications:enableCta", table: "Localizable") }
        public static func hoursAgo(count: String) -> String {
            String(format: String(localized: "notifications:hoursAgo", table: "Localizable"), count)
        }
        public static var justNow: String { String(localized: "notifications:justNow", table: "Localizable") }
        public static var markAllRead: String { String(localized: "notifications:markAllRead", table: "Localizable") }
        public static func minutesAgo(count: String) -> String {
            String(format: String(localized: "notifications:minutesAgo", table: "Localizable"), count)
        }
        public static var settings: String { String(localized: "notifications:settings", table: "Localizable") }
        public static var title: String { String(localized: "notifications:title", table: "Localizable") }
    }

    public enum Onboarding {
        public static var createAccount: String { String(localized: "onboarding:createAccount", table: "Localizable") }
        public static var footer: String { String(localized: "onboarding:footer", table: "Localizable") }
        public static var guestErr: String { String(localized: "onboarding:guestErr", table: "Localizable") }
        public static var installApp: String { String(localized: "onboarding:installApp", table: "Localizable") }
        public static var installTitle: String { String(localized: "onboarding:installTitle", table: "Localizable") }
        public static var next: String { String(localized: "onboarding:next", table: "Localizable") }
        public static var signIn: String { String(localized: "onboarding:signIn", table: "Localizable") }
        public static var skip: String { String(localized: "onboarding:skip", table: "Localizable") }
        public static var slides0Body: String { String(localized: "onboarding:slides.0.body", table: "Localizable") }
        public static var slides0Title: String { String(localized: "onboarding:slides.0.title", table: "Localizable") }
        public static var slides1Body: String { String(localized: "onboarding:slides.1.body", table: "Localizable") }
        public static var slides1Title: String { String(localized: "onboarding:slides.1.title", table: "Localizable") }
        public static var slides2Body: String { String(localized: "onboarding:slides.2.body", table: "Localizable") }
        public static var slides2Title: String { String(localized: "onboarding:slides.2.title", table: "Localizable") }
        public static var slides3Body: String { String(localized: "onboarding:slides.3.body", table: "Localizable") }
        public static var slides3Title: String { String(localized: "onboarding:slides.3.title", table: "Localizable") }
        public static var slides4Body: String { String(localized: "onboarding:slides.4.body", table: "Localizable") }
        public static var slides4Title: String { String(localized: "onboarding:slides.4.title", table: "Localizable") }
        public static var slides5Body: String { String(localized: "onboarding:slides.5.body", table: "Localizable") }
        public static var slides5Title: String { String(localized: "onboarding:slides.5.title", table: "Localizable") }
        public static var slides6Body: String { String(localized: "onboarding:slides.6.body", table: "Localizable") }
        public static var slides6Title: String { String(localized: "onboarding:slides.6.title", table: "Localizable") }
        public static var starting: String { String(localized: "onboarding:starting", table: "Localizable") }
        public static var tryGuest: String { String(localized: "onboarding:tryGuest", table: "Localizable") }
        public static var wtAccBalHelp: String { String(localized: "onboarding:wt.acc.balHelp", table: "Localizable") }
        public static var wtAccBalLabel: String { String(localized: "onboarding:wt.acc.balLabel", table: "Localizable") }
        public static var wtAccCta: String { String(localized: "onboarding:wt.acc.cta", table: "Localizable") }
        public static var wtAccEg1: String { String(localized: "onboarding:wt.acc.eg1", table: "Localizable") }
        public static var wtAccEg2: String { String(localized: "onboarding:wt.acc.eg2", table: "Localizable") }
        public static var wtAccNameLabel: String { String(localized: "onboarding:wt.acc.nameLabel", table: "Localizable") }
        public static var wtAccP1: String { String(localized: "onboarding:wt.acc.p1", table: "Localizable") }
        public static var wtAccP2: String { String(localized: "onboarding:wt.acc.p2", table: "Localizable") }
        public static var wtAccTitle: String { String(localized: "onboarding:wt.acc.title", table: "Localizable") }
        public static var wtAskP1: String { String(localized: "onboarding:wt.ask.p1", table: "Localizable") }
        public static var wtAskP2: String { String(localized: "onboarding:wt.ask.p2", table: "Localizable") }
        public static var wtAskPrivacy: String { String(localized: "onboarding:wt.ask.privacy", table: "Localizable") }
        public static var wtAskTitle: String { String(localized: "onboarding:wt.ask.title", table: "Localizable") }
        public static var wtDialogLabel: String { String(localized: "onboarding:wt.dialogLabel", table: "Localizable") }
        public static var wtDoneBudgetBody: String { String(localized: "onboarding:wt.done.budgetBody", table: "Localizable") }
        public static var wtDoneBudgetTitle: String { String(localized: "onboarding:wt.done.budgetTitle", table: "Localizable") }
        public static var wtDoneCta: String { String(localized: "onboarding:wt.done.cta", table: "Localizable") }
        public static var wtDoneDashBody: String { String(localized: "onboarding:wt.done.dashBody", table: "Localizable") }
        public static var wtDoneDashTitle: String { String(localized: "onboarding:wt.done.dashTitle", table: "Localizable") }
        public static var wtDoneMore: String { String(localized: "onboarding:wt.done.more", table: "Localizable") }
        public static var wtDonePrivacy: String { String(localized: "onboarding:wt.done.privacy", table: "Localizable") }
        public static var wtDoneTitle: String { String(localized: "onboarding:wt.done.title", table: "Localizable") }
        public static var wtDoneTxnBody: String { String(localized: "onboarding:wt.done.txnBody", table: "Localizable") }
        public static var wtDoneTxnTitle: String { String(localized: "onboarding:wt.done.txnTitle", table: "Localizable") }
        public static var wtGuestCta: String { String(localized: "onboarding:wt.guest.cta", table: "Localizable") }
        public static var wtGuestLater: String { String(localized: "onboarding:wt.guest.later", table: "Localizable") }
        public static var wtGuestP1: String { String(localized: "onboarding:wt.guest.p1", table: "Localizable") }
        public static var wtGuestTitle: String { String(localized: "onboarding:wt.guest.title", table: "Localizable") }
        public static var wtInsightsEg: String { String(localized: "onboarding:wt.insights.eg", table: "Localizable") }
        public static var wtInsightsP1: String { String(localized: "onboarding:wt.insights.p1", table: "Localizable") }
        public static var wtInsightsP2: String { String(localized: "onboarding:wt.insights.p2", table: "Localizable") }
        public static var wtInsightsTitle: String { String(localized: "onboarding:wt.insights.title", table: "Localizable") }
        public static var wtIntroCta: String { String(localized: "onboarding:wt.intro.cta", table: "Localizable") }
        public static var wtIntroP1: String { String(localized: "onboarding:wt.intro.p1", table: "Localizable") }
        public static var wtIntroP2: String { String(localized: "onboarding:wt.intro.p2", table: "Localizable") }
        public static var wtIntroP3: String { String(localized: "onboarding:wt.intro.p3", table: "Localizable") }
        public static var wtIntroP4: String { String(localized: "onboarding:wt.intro.p4", table: "Localizable") }
        public static var wtIntroTitle: String { String(localized: "onboarding:wt.intro.title", table: "Localizable") }
        public static var wtLater: String { String(localized: "onboarding:wt.later", table: "Localizable") }
        public static var wtNext: String { String(localized: "onboarding:wt.next", table: "Localizable") }
        public static var wtPlanCta: String { String(localized: "onboarding:wt.plan.cta", table: "Localizable") }
        public static var wtPlanFree: String { String(localized: "onboarding:wt.plan.free", table: "Localizable") }
        public static func wtPlanPerMonth(amount: String) -> String {
            String(format: String(localized: "onboarding:wt.plan.perMonth", table: "Localizable"), amount)
        }
        public static func wtPlanQuota(count: String) -> String {
            String(format: String(localized: "onboarding:wt.plan.quota", table: "Localizable"), count)
        }
        public static var wtPlanSee: String { String(localized: "onboarding:wt.plan.see", table: "Localizable") }
        public static var wtPlanTitle: String { String(localized: "onboarding:wt.plan.title", table: "Localizable") }
        public static var wtPlanTitleTrial: String { String(localized: "onboarding:wt.plan.titleTrial", table: "Localizable") }
        public static var wtPlanTrial: String { String(localized: "onboarding:wt.plan.trial", table: "Localizable") }
        public static func wtProgress(step: String, of: String) -> String {
            String(format: String(localized: "onboarding:wt.progress", table: "Localizable"), step, of)
        }
        public static var wtSaving: String { String(localized: "onboarding:wt.saving", table: "Localizable") }
        public static var wtSkip: String { String(localized: "onboarding:wt.skip", table: "Localizable") }
        public static var wtSpendAmountLabel: String { String(localized: "onboarding:wt.spend.amountLabel", table: "Localizable") }
        public static var wtSpendCta: String { String(localized: "onboarding:wt.spend.cta", table: "Localizable") }
        public static var wtSpendP1: String { String(localized: "onboarding:wt.spend.p1", table: "Localizable") }
        public static var wtSpendP2: String { String(localized: "onboarding:wt.spend.p2", table: "Localizable") }
        public static var wtSpendP3: String { String(localized: "onboarding:wt.spend.p3", table: "Localizable") }
        public static var wtSpendTitle: String { String(localized: "onboarding:wt.spend.title", table: "Localizable") }
        public static var wtSpendWhatEg: String { String(localized: "onboarding:wt.spend.whatEg", table: "Localizable") }
        public static var wtSpendWhatLabel: String { String(localized: "onboarding:wt.spend.whatLabel", table: "Localizable") }
    }

    public enum Payments {
        public static func confirmClaim(name: String) -> String {
            String(format: String(localized: "payments:confirm.claim", table: "Localizable"), name)
        }
        public static var confirmIntro: String { String(localized: "payments:confirm.intro", table: "Localizable") }
        public static var confirmNo: String { String(localized: "payments:confirm.no", table: "Localizable") }
        public static var confirmNoAccount: String { String(localized: "payments:confirm.noAccount", table: "Localizable") }
        public static var confirmPendingChip: String { String(localized: "payments:confirm.pendingChip", table: "Localizable") }
        public static var confirmReceivedInto: String { String(localized: "payments:confirm.receivedInto", table: "Localizable") }
        public static func confirmReference(ref: String) -> String {
            String(format: String(localized: "payments:confirm.reference", table: "Localizable"), ref)
        }
        public static var confirmTitle: String { String(localized: "payments:confirm.title", table: "Localizable") }
        public static var confirmYes: String { String(localized: "payments:confirm.yes", table: "Localizable") }
        public static var payAfterPaying: String { String(localized: "payments:pay.afterPaying", table: "Localizable") }
        public static var payBack: String { String(localized: "payments:pay.back", table: "Localizable") }
        public static var payButton: String { String(localized: "payments:pay.button", table: "Localizable") }
        public static var payCopied: String { String(localized: "payments:pay.copied", table: "Localizable") }
        public static var payCopyAmount: String { String(localized: "payments:pay.copyAmount", table: "Localizable") }
        public static var payCopyId: String { String(localized: "payments:pay.copyId", table: "Localizable") }
        public static var payDidntOpen: String { String(localized: "payments:pay.didntOpen", table: "Localizable") }
        public static var payManualTitle: String { String(localized: "payments:pay.manualTitle", table: "Localizable") }
        public static var payMarkPaid: String { String(localized: "payments:pay.markPaid", table: "Localizable") }
        public static func payNoCallbackNote(name: String) -> String {
            String(format: String(localized: "payments:pay.noCallbackNote", table: "Localizable"), name)
        }
        public static func payNoHandle(name: String) -> String {
            String(format: String(localized: "payments:pay.noHandle", table: "Localizable"), name)
        }
        public static var payOpenApp: String { String(localized: "payments:pay.openApp", table: "Localizable") }
        public static var payPayingTo: String { String(localized: "payments:pay.payingTo", table: "Localizable") }
        public static var payPreparing: String { String(localized: "payments:pay.preparing", table: "Localizable") }
        public static var payQrAlt: String { String(localized: "payments:pay.qrAlt", table: "Localizable") }
        public static var payQrHintMobile: String { String(localized: "payments:pay.qrHintMobile", table: "Localizable") }
        public static var payScanHint: String { String(localized: "payments:pay.scanHint", table: "Localizable") }
        public static var payAnyoneAmount: String { String(localized: "payments:payAnyone.amount", table: "Localizable") }
        public static var payAnyoneCancelScan: String { String(localized: "payments:payAnyone.cancelScan", table: "Localizable") }
        public static func payAnyoneClaimsName(name: String) -> String {
            String(format: String(localized: "payments:payAnyone.claimsName", table: "Localizable"), name)
        }
        public static var payAnyoneClose: String { String(localized: "payments:payAnyone.close", table: "Localizable") }
        public static var payAnyoneErrBadVpa: String { String(localized: "payments:payAnyone.err.bad_vpa", table: "Localizable") }
        public static var payAnyoneErrEmpty: String { String(localized: "payments:payAnyone.err.empty", table: "Localizable") }
        public static var payAnyoneErrEmvco: String { String(localized: "payments:payAnyone.err.emvco", table: "Localizable") }
        public static var payAnyoneErrNotUpi: String { String(localized: "payments:payAnyone.err.not_upi", table: "Localizable") }
        public static var payAnyoneErrOther: String { String(localized: "payments:payAnyone.err.other", table: "Localizable") }
        public static var payAnyoneErrUnsupportedCurrency: String { String(localized: "payments:payAnyone.err.unsupported_currency", table: "Localizable") }
        public static var payAnyoneFootnote: String { String(localized: "payments:payAnyone.footnote", table: "Localizable") }
        public static var payAnyoneNotePlaceholder: String { String(localized: "payments:payAnyone.notePlaceholder", table: "Localizable") }
        public static var payAnyonePay: String { String(localized: "payments:payAnyone.pay", table: "Localizable") }
        public static var payAnyonePayAmount: String { String(localized: "payments:payAnyone.payAmount", table: "Localizable") }
        public static var payAnyoneScanCta: String { String(localized: "payments:payAnyone.scanCta", table: "Localizable") }
        public static var payAnyoneScanHint: String { String(localized: "payments:payAnyone.scanHint", table: "Localizable") }
        public static var payAnyoneSubtitle: String { String(localized: "payments:payAnyone.subtitle", table: "Localizable") }
        public static var payAnyoneTitle: String { String(localized: "payments:payAnyone.title", table: "Localizable") }
        public static var payAnyoneUpiId: String { String(localized: "payments:payAnyone.upiId", table: "Localizable") }
        public static var settingsCurrent: String { String(localized: "payments:settings.current", table: "Localizable") }
        public static var settingsGuestBlocked: String { String(localized: "payments:settings.guestBlocked", table: "Localizable") }
        public static var settingsHideLog: String { String(localized: "payments:settings.hideLog", table: "Localizable") }
        public static var settingsIntro: String { String(localized: "payments:settings.intro", table: "Localizable") }
        public static var settingsInvalid: String { String(localized: "payments:settings.invalid", table: "Localizable") }
        public static var settingsLabel: String { String(localized: "payments:settings.label", table: "Localizable") }
        public static var settingsPrivacy: String { String(localized: "payments:settings.privacy", table: "Localizable") }
        public static var settingsRemove: String { String(localized: "payments:settings.remove", table: "Localizable") }
        public static var settingsReplace: String { String(localized: "payments:settings.replace", table: "Localizable") }
        public static var settingsSave: String { String(localized: "payments:settings.save", table: "Localizable") }
        public static func settingsShowLog(count: String) -> String {
            String(format: String(localized: "payments:settings.showLog", table: "Localizable"), count)
        }
        public static var settingsSomeone: String { String(localized: "payments:settings.someone", table: "Localizable") }
        public static var settingsTitle: String { String(localized: "payments:settings.title", table: "Localizable") }
        public static var settingsUpdate: String { String(localized: "payments:settings.update", table: "Localizable") }
        public static func settingsWillShow(masked: String) -> String {
            String(format: String(localized: "payments:settings.willShow", table: "Localizable"), masked)
        }
        public static var someone: String { String(localized: "payments:someone", table: "Localizable") }
    }

    public enum Receipts {
        public static var breakdownEveryone: String { String(localized: "receipts:breakdown.everyone", table: "Localizable") }
        public static var breakdownHide: String { String(localized: "receipts:breakdown.hide", table: "Localizable") }
        public static func breakdownPersonTotal(name: String) -> String {
            String(format: String(localized: "receipts:breakdown.personTotal", table: "Localizable"), name)
        }
        public static var breakdownShow: String { String(localized: "receipts:breakdown.show", table: "Localizable") }
        public static var captureAiNote: String { String(localized: "receipts:capture.aiNote", table: "Localizable") }
        public static func captureCreditsLeft(count: String) -> String {
            String(format: String(localized: "receipts:capture.creditsLeft", table: "Localizable"), count)
        }
        public static var captureDropHint: String { String(localized: "receipts:capture.dropHint", table: "Localizable") }
        public static var captureEditManually: String { String(localized: "receipts:capture.editManually", table: "Localizable") }
        public static var captureImproveWithAi: String { String(localized: "receipts:capture.improveWithAi", table: "Localizable") }
        public static var captureIntro: String { String(localized: "receipts:capture.intro", table: "Localizable") }
        public static var captureNoCredits: String { String(localized: "receipts:capture.noCredits", table: "Localizable") }
        public static var capturePasswordPlaceholder: String { String(localized: "receipts:capture.passwordPlaceholder", table: "Localizable") }
        public static var capturePdfPassword: String { String(localized: "receipts:capture.pdfPassword", table: "Localizable") }
        public static var capturePreviewAlt: String { String(localized: "receipts:capture.previewAlt", table: "Localizable") }
        public static var capturePrivacy: String { String(localized: "receipts:capture.privacy", table: "Localizable") }
        public static var captureRetake: String { String(localized: "receipts:capture.retake", table: "Localizable") }
        public static var captureSeePlans: String { String(localized: "receipts:capture.seePlans", table: "Localizable") }
        public static var captureTakePhoto: String { String(localized: "receipts:capture.takePhoto", table: "Localizable") }
        public static var captureTitle: String { String(localized: "receipts:capture.title", table: "Localizable") }
        public static var captureUnclearMismatch: String { String(localized: "receipts:capture.unclear.mismatch", table: "Localizable") }
        public static var captureUnclearNoLines: String { String(localized: "receipts:capture.unclear.noLines", table: "Localizable") }
        public static var captureUnclearNoTotal: String { String(localized: "receipts:capture.unclear.noTotal", table: "Localizable") }
        public static var captureUnclearTitle: String { String(localized: "receipts:capture.unclear.title", table: "Localizable") }
        public static var captureUnlock: String { String(localized: "receipts:capture.unlock", table: "Localizable") }
        public static var captureUpload: String { String(localized: "receipts:capture.upload", table: "Localizable") }
        public static var errorsPdfLocked: String { String(localized: "receipts:errors.pdfLocked", table: "Localizable") }
        public static var kindDiscount: String { String(localized: "receipts:kind.discount", table: "Localizable") }
        public static var kindItem: String { String(localized: "receipts:kind.item", table: "Localizable") }
        public static var kindServiceCharge: String { String(localized: "receipts:kind.service_charge", table: "Localizable") }
        public static var kindTax: String { String(localized: "receipts:kind.tax", table: "Localizable") }
        public static var kindTip: String { String(localized: "receipts:kind.tip", table: "Localizable") }
        public static var modeEqual: String { String(localized: "receipts:mode.equal", table: "Localizable") }
        public static var modeExact: String { String(localized: "receipts:mode.exact", table: "Localizable") }
        public static var modePercent: String { String(localized: "receipts:mode.percent", table: "Localizable") }
        public static var modeProportional: String { String(localized: "receipts:mode.proportional", table: "Localizable") }
        public static var modeQuantity: String { String(localized: "receipts:mode.quantity", table: "Localizable") }
        public static var reviewAccount: String { String(localized: "receipts:review.account", table: "Localizable") }
        public static var reviewAddCharge: String { String(localized: "receipts:review.addCharge", table: "Localizable") }
        public static func reviewAddDifference(amount: String) -> String {
            String(format: String(localized: "receipts:review.addDifference", table: "Localizable"), amount)
        }
        public static var reviewAddItem: String { String(localized: "receipts:review.addItem", table: "Localizable") }
        public static var reviewAmount: String { String(localized: "receipts:review.amount", table: "Localizable") }
        public static func reviewBalanced(total: String) -> String {
            String(format: String(localized: "receipts:review.balanced", table: "Localizable"), total)
        }
        public static var reviewCategory: String { String(localized: "receipts:review.category", table: "Localizable") }
        public static var reviewContinueToSplit: String { String(localized: "receipts:review.continueToSplit", table: "Localizable") }
        public static var reviewCorrupt: String { String(localized: "receipts:review.corrupt", table: "Localizable") }
        public static var reviewDate: String { String(localized: "receipts:review.date", table: "Localizable") }
        public static var reviewDescription: String { String(localized: "receipts:review.description", table: "Localizable") }
        public static var reviewGroup: String { String(localized: "receipts:review.group", table: "Localizable") }
        public static var reviewIntro: String { String(localized: "receipts:review.intro", table: "Localizable") }
        public static var reviewItems: String { String(localized: "receipts:review.items", table: "Localizable") }
        public static var reviewJustRecord: String { String(localized: "receipts:review.justRecord", table: "Localizable") }
        public static var reviewKind: String { String(localized: "receipts:review.kind", table: "Localizable") }
        public static func reviewLineCount(count: Int) -> String {
            String(format: String(localized: "receipts:review.lineCount", defaultValue: "", table: "Localizable"), count)
        }
        public static var reviewMerchant: String { String(localized: "receipts:review.merchant", table: "Localizable") }
        public static var reviewMerchantPlaceholder: String { String(localized: "receipts:review.merchantPlaceholder", table: "Localizable") }
        public static var reviewMustBalance: String { String(localized: "receipts:review.mustBalance", table: "Localizable") }
        public static var reviewNeedTotal: String { String(localized: "receipts:review.needTotal", table: "Localizable") }
        public static var reviewNewGroup: String { String(localized: "receipts:review.newGroup", table: "Localizable") }
        public static var reviewNewGroupName: String { String(localized: "receipts:review.newGroupName", table: "Localizable") }
        public static var reviewNewGroupPlaceholder: String { String(localized: "receipts:review.newGroupPlaceholder", table: "Localizable") }
        public static var reviewNoCategory: String { String(localized: "receipts:review.noCategory", table: "Localizable") }
        public static var reviewNotFound: String { String(localized: "receipts:review.notFound", table: "Localizable") }
        public static func reviewOffBy(computed: String, stated: String) -> String {
            String(format: String(localized: "receipts:review.offBy", table: "Localizable"), computed, stated)
        }
        public static var reviewPickGroup: String { String(localized: "receipts:review.pickGroup", table: "Localizable") }
        public static var reviewQty: String { String(localized: "receipts:review.qty", table: "Localizable") }
        public static var reviewRemoveLine: String { String(localized: "receipts:review.removeLine", table: "Localizable") }
        public static var reviewSave: String { String(localized: "receipts:review.save", table: "Localizable") }
        public static var reviewSplitIt: String { String(localized: "receipts:review.splitIt", table: "Localizable") }
        public static var reviewSplitNote: String { String(localized: "receipts:review.splitNote", table: "Localizable") }
        public static var reviewSubtotalItems: String { String(localized: "receipts:review.subtotalItems", table: "Localizable") }
        public static var reviewTitle: String { String(localized: "receipts:review.title", table: "Localizable") }
        public static var reviewTotal: String { String(localized: "receipts:review.total", table: "Localizable") }
        public static var reviewUnmatched: String { String(localized: "receipts:review.unmatched", table: "Localizable") }
        public static func reviewUseComputed(amount: String) -> String {
            String(format: String(localized: "receipts:review.useComputed", table: "Localizable"), amount)
        }
        public static var splitCorrupt: String { String(localized: "receipts:split.corrupt", table: "Localizable") }
        public static var splitEveryoneAll: String { String(localized: "receipts:split.everyoneAll", table: "Localizable") }
        public static func splitExactMismatch(diff: String) -> String {
            String(format: String(localized: "receipts:split.exactMismatch", table: "Localizable"), diff)
        }
        public static var splitFixLines: String { String(localized: "receipts:split.fixLines", table: "Localizable") }
        public static var splitIntro: String { String(localized: "receipts:split.intro", table: "Localizable") }
        public static var splitNeedsSomeone: String { String(localized: "receipts:split.needsSomeone", table: "Localizable") }
        public static var splitNotFound: String { String(localized: "receipts:split.notFound", table: "Localizable") }
        public static var splitOnlyMe: String { String(localized: "receipts:split.onlyMe", table: "Localizable") }
        public static func splitPercentMismatch(pct: String) -> String {
            String(format: String(localized: "receipts:split.percentMismatch", table: "Localizable"), pct)
        }
        public static func splitQtyLabel(qty: String, unit: String) -> String {
            String(format: String(localized: "receipts:split.qtyLabel", table: "Localizable"), qty, unit)
        }
        public static func splitQtyMismatch(got: String, want: String) -> String {
            String(format: String(localized: "receipts:split.qtyMismatch", table: "Localizable"), got, want)
        }
        public static var splitQuick: String { String(localized: "receipts:split.quick", table: "Localizable") }
        public static var splitSave: String { String(localized: "receipts:split.save", table: "Localizable") }
        public static var splitSomeone: String { String(localized: "receipts:split.someone", table: "Localizable") }
        public static var splitTitle: String { String(localized: "receipts:split.title", table: "Localizable") }
        public static var splitTotal: String { String(localized: "receipts:split.total", table: "Localizable") }
        public static var splitYou: String { String(localized: "receipts:split.you", table: "Localizable") }
        public static var stageDone: String { String(localized: "receipts:stage.done", table: "Localizable") }
        public static var stagePreparing: String { String(localized: "receipts:stage.preparing", table: "Localizable") }
        public static var stageReading: String { String(localized: "receipts:stage.reading", table: "Localizable") }
        public static var stageUnderstanding: String { String(localized: "receipts:stage.understanding", table: "Localizable") }
    }

    public enum Recurring {
        public static func actions(name: String) -> String {
            String(format: String(localized: "recurring:actions", table: "Localizable"), name)
        }
        public static var add: String { String(localized: "recurring:add", table: "Localizable") }
        public static var amountLabel: String { String(localized: "recurring:amountLabel", table: "Localizable") }
        public static var autoPosts: String { String(localized: "recurring:autoPosts", table: "Localizable") }
        public static var cancel: String { String(localized: "recurring:cancel", table: "Localizable") }
        public static var confirm: String { String(localized: "recurring:confirm", table: "Localizable") }
        public static var create: String { String(localized: "recurring:create", table: "Localizable") }
        public static var dueNow: String { String(localized: "recurring:dueNow", table: "Localizable") }
        public static func dueOn(date: String) -> String {
            String(format: String(localized: "recurring:dueOn", table: "Localizable"), date)
        }
        public static var edit: String { String(localized: "recurring:edit", table: "Localizable") }
        public static var emptyIncome: String { String(localized: "recurring:emptyIncome", table: "Localizable") }
        public static var emptyPayment: String { String(localized: "recurring:emptyPayment", table: "Localizable") }
        public static var emptySaving: String { String(localized: "recurring:emptySaving", table: "Localizable") }
        public static var freqDaily: String { String(localized: "recurring:freq.daily", table: "Localizable") }
        public static var freqMonthly: String { String(localized: "recurring:freq.monthly", table: "Localizable") }
        public static var freqWeekly: String { String(localized: "recurring:freq.weekly", table: "Localizable") }
        public static var freqYearly: String { String(localized: "recurring:freq.yearly", table: "Localizable") }
        public static var groupDelete: String { String(localized: "recurring:groupDelete", table: "Localizable") }
        public static var groupDeleteEmpty: String { String(localized: "recurring:groupDeleteEmpty", table: "Localizable") }
        public static var groupDeleteLast: String { String(localized: "recurring:groupDeleteLast", table: "Localizable") }
        public static func groupDeleteMove(count: Int) -> String {
            String(format: String(localized: "recurring:groupDeleteMove", defaultValue: "", table: "Localizable"), count)
        }
        public static func groupDeleteTitle(name: String) -> String {
            String(format: String(localized: "recurring:groupDeleteTitle", table: "Localizable"), name)
        }
        public static var groupEmpty: String { String(localized: "recurring:groupEmpty", table: "Localizable") }
        public static var groupNewCta: String { String(localized: "recurring:groupNewCta", table: "Localizable") }
        public static var income: String { String(localized: "recurring:income", table: "Localizable") }
        public static var incomes: String { String(localized: "recurring:incomes", table: "Localizable") }
        public static func itemCount(count: Int) -> String {
            String(format: String(localized: "recurring:itemCount", defaultValue: "", table: "Localizable"), count)
        }
        public static var netMonthly: String { String(localized: "recurring:netMonthly", table: "Localizable") }
        public static func next(date: String) -> String {
            String(format: String(localized: "recurring:next", table: "Localizable"), date)
        }
        public static var payment: String { String(localized: "recurring:payment", table: "Localizable") }
        public static var payments: String { String(localized: "recurring:payments", table: "Localizable") }
        public static var perMonth: String { String(localized: "recurring:perMonth", table: "Localizable") }
        public static var perMonthLabel: String { String(localized: "recurring:perMonthLabel", table: "Localizable") }
        public static var postNow: String { String(localized: "recurring:postNow", table: "Localizable") }
        public static var record: String { String(localized: "recurring:record", table: "Localizable") }
        public static var remove: String { String(localized: "recurring:remove", table: "Localizable") }
        public static func removeMsg(name: String) -> String {
            String(format: String(localized: "recurring:removeMsg", table: "Localizable"), name)
        }
        public static var removeTitle: String { String(localized: "recurring:removeTitle", table: "Localizable") }
        public static var skip: String { String(localized: "recurring:skip", table: "Localizable") }
        public static var subtitleLink: String { String(localized: "recurring:subtitleLink", table: "Localizable") }
        public static var subtitlePre: String { String(localized: "recurring:subtitlePre", table: "Localizable") }
        public static var title: String { String(localized: "recurring:title", table: "Localizable") }
    }

    public enum Reflect {
        public static var doneBody: String { String(localized: "reflect:doneBody", table: "Localizable") }
        public static var doneTitle: String { String(localized: "reflect:doneTitle", table: "Localizable") }
        public static var greed: String { String(localized: "reflect:greed", table: "Localizable") }
        public static var hint: String { String(localized: "reflect:hint", table: "Localizable") }
        public static func left(count: String) -> String {
            String(format: String(localized: "reflect:left", table: "Localizable"), count)
        }
        public static var need: String { String(localized: "reflect:need", table: "Localizable") }
        public static var skip: String { String(localized: "reflect:skip", table: "Localizable") }
        public static var title: String { String(localized: "reflect:title", table: "Localizable") }
        public static var undo: String { String(localized: "reflect:undo", table: "Localizable") }
        public static var unknown: String { String(localized: "reflect:unknown", table: "Localizable") }
    }

    public enum Search {
        public static var allAccounts: String { String(localized: "search:allAccounts", table: "Localizable") }
        public static var clear: String { String(localized: "search:clear", table: "Localizable") }
        public static var filters: String { String(localized: "search:filters", table: "Localizable") }
        public static var fromDate: String { String(localized: "search:fromDate", table: "Localizable") }
        public static var maxAmount: String { String(localized: "search:maxAmount", table: "Localizable") }
        public static var minAmount: String { String(localized: "search:minAmount", table: "Localizable") }
        public static var noMatching: String { String(localized: "search:noMatching", table: "Localizable") }
        public static func resultsCount(count: Int) -> String {
            String(format: String(localized: "search:resultsCount", defaultValue: "", table: "Localizable"), count)
        }
        public static var searchEverything: String { String(localized: "search:searchEverything", table: "Localizable") }
        public static var title: String { String(localized: "search:title", table: "Localizable") }
        public static var toDate: String { String(localized: "search:toDate", table: "Localizable") }
        public static var typeAll: String { String(localized: "search:type.all", table: "Localizable") }
        public static var typeExpense: String { String(localized: "search:type.expense", table: "Localizable") }
        public static var typeIncome: String { String(localized: "search:type.income", table: "Localizable") }
        public static var typeTransfer: String { String(localized: "search:type.transfer", table: "Localizable") }
    }

    public enum Settings {
        public static var account: String { String(localized: "settings:account", table: "Localizable") }
        public static var allSynced: String { String(localized: "settings:allSynced", table: "Localizable") }
        public static var appearance: String { String(localized: "settings:appearance", table: "Localizable") }
        public static var baseCurrency: String { String(localized: "settings:baseCurrency", table: "Localizable") }
        public static var baseCurrencyDesc: String { String(localized: "settings:baseCurrencyDesc", table: "Localizable") }
        public static var cancel: String { String(localized: "settings:cancel", table: "Localizable") }
        public static var catsLabels: String { String(localized: "settings:catsLabels", table: "Localizable") }
        public static var catsLabelsDesc: String { String(localized: "settings:catsLabelsDesc", table: "Localizable") }
        public static var connecting: String { String(localized: "settings:connecting", table: "Localizable") }
        public static var contactSupport: String { String(localized: "settings:contactSupport", table: "Localizable") }
        public static var createAccount: String { String(localized: "settings:createAccount", table: "Localizable") }
        public static var createToKeep: String { String(localized: "settings:createToKeep", table: "Localizable") }
        public static var dark: String { String(localized: "settings:dark", table: "Localizable") }
        public static var deleteAccount: String { String(localized: "settings:deleteAccount", table: "Localizable") }
        public static var deleteBody: String { String(localized: "settings:deleteBody", table: "Localizable") }
        public static var deleteErrDefault: String { String(localized: "settings:deleteErrDefault", table: "Localizable") }
        public static var deleteEverything: String { String(localized: "settings:deleteEverything", table: "Localizable") }
        public static var deleteTitle: String { String(localized: "settings:deleteTitle", table: "Localizable") }
        public static var deleting: String { String(localized: "settings:deleting", table: "Localizable") }
        public static var displayName: String { String(localized: "settings:displayName", table: "Localizable") }
        public static var guestBold: String { String(localized: "settings:guestBold", table: "Localizable") }
        public static func guestDelete(count: Int) -> String {
            String(format: String(localized: "settings:guestDelete", defaultValue: "", table: "Localizable"), count)
        }
        public static var guestDot: String { String(localized: "settings:guestDot", table: "Localizable") }
        public static var guestPre: String { String(localized: "settings:guestPre", table: "Localizable") }
        public static var guestSignoutWarn: String { String(localized: "settings:guestSignoutWarn", table: "Localizable") }
        public static var help: String { String(localized: "settings:help", table: "Localizable") }
        public static var helpNote: String { String(localized: "settings:helpNote", table: "Localizable") }
        public static var hidden: String { String(localized: "settings:hidden", table: "Localizable") }
        public static var hideAmounts: String { String(localized: "settings:hideAmounts", table: "Localizable") }
        public static var hideAmountsDesc: String { String(localized: "settings:hideAmountsDesc", table: "Localizable") }
        public static var importExport: String { String(localized: "settings:importExport", table: "Localizable") }
        public static var importExportBtn: String { String(localized: "settings:importExportBtn", table: "Localizable") }
        public static var importExportDesc: String { String(localized: "settings:importExportDesc", table: "Localizable") }
        public static var language: String { String(localized: "settings:language", table: "Localizable") }
        public static var light: String { String(localized: "settings:light", table: "Localizable") }
        public static var manageCategories: String { String(localized: "settings:manageCategories", table: "Localizable") }
        public static var manageLabels: String { String(localized: "settings:manageLabels", table: "Localizable") }
        public static var privacy: String { String(localized: "settings:privacy", table: "Localizable") }
        public static var replayConfirm: String { String(localized: "settings:replayConfirm", table: "Localizable") }
        public static var replayIntro: String { String(localized: "settings:replayIntro", table: "Localizable") }
        public static var replayMsg: String { String(localized: "settings:replayMsg", table: "Localizable") }
        public static var replayTitle: String { String(localized: "settings:replayTitle", table: "Localizable") }
        public static var save: String { String(localized: "settings:save", table: "Localizable") }
        public static var saved: String { String(localized: "settings:saved", table: "Localizable") }
        public static var signedInAs: String { String(localized: "settings:signedInAs", table: "Localizable") }
        public static var signOut: String { String(localized: "settings:signOut", table: "Localizable") }
        public static var signOutAnyway: String { String(localized: "settings:signOutAnyway", table: "Localizable") }
        public static var signoutRestore: String { String(localized: "settings:signoutRestore", table: "Localizable") }
        public static var signoutTitle: String { String(localized: "settings:signoutTitle", table: "Localizable") }
        public static func synced(time: String) -> String {
            String(format: String(localized: "settings:synced", table: "Localizable"), time)
        }
        public static var syncing: String { String(localized: "settings:syncing", table: "Localizable") }
        public static var title: String { String(localized: "settings:title", table: "Localizable") }
        public static var visible: String { String(localized: "settings:visible", table: "Localizable") }
        public static var yourName: String { String(localized: "settings:yourName", table: "Localizable") }
    }

    public enum Splits {
        public static var addExpense: String { String(localized: "splits:addExpense", table: "Localizable") }
        public static func amountLabel(currency: String) -> String {
            String(format: String(localized: "splits:amountLabel", table: "Localizable"), currency)
        }
        public static var cancel: String { String(localized: "splits:cancel", table: "Localizable") }
        public static var copied: String { String(localized: "splits:copied", table: "Localizable") }
        public static var emptyBodyLink: String { String(localized: "splits:empty.bodyLink", table: "Localizable") }
        public static var emptyBodyPost: String { String(localized: "splits:empty.bodyPost", table: "Localizable") }
        public static var emptyBodyPre: String { String(localized: "splits:empty.bodyPre", table: "Localizable") }
        public static var emptyTitle: String { String(localized: "splits:empty.title", table: "Localizable") }
        public static var eyebrow: String { String(localized: "splits:eyebrow", table: "Localizable") }
        public static var groupsAndTrips: String { String(localized: "splits:groupsAndTrips", table: "Localizable") }
        public static var hideLines: String { String(localized: "splits:hideLines", table: "Localizable") }
        public static var insightsAlwaysOwed: String { String(localized: "splits:insights.always_owed", table: "Localizable") }
        public static var insightsAlwaysOwes: String { String(localized: "splits:insights.always_owes", table: "Localizable") }
        public static var insightsBiggestLender: String { String(localized: "splits:insights.biggest_lender", table: "Localizable") }
        public static func insightsDays(count: Int) -> String {
            String(format: String(localized: "splits:insights.days", defaultValue: "", table: "Localizable"), count)
        }
        public static var insightsFastestSettler: String { String(localized: "splits:insights.fastest_settler", table: "Localizable") }
        public static var insightsFootnote: String { String(localized: "splits:insights.footnote", table: "Localizable") }
        public static func insightsGroups(count: Int) -> String {
            String(format: String(localized: "splits:insights.groups", defaultValue: "", table: "Localizable"), count)
        }
        public static var insightsOwesYouMost: String { String(localized: "splits:insights.owes_you_most", table: "Localizable") }
        public static var insightsSlowestSettler: String { String(localized: "splits:insights.slowest_settler", table: "Localizable") }
        public static var insightsYouOweMost: String { String(localized: "splits:insights.you_owe_most", table: "Localizable") }
        public static var kindGroup: String { String(localized: "splits:kind.group", table: "Localizable") }
        public static var kindTrip: String { String(localized: "splits:kind.trip", table: "Localizable") }
        public static func membersLine(count: Int, kind: String) -> String {
            String(format: String(localized: "splits:membersLine", defaultValue: "", table: "Localizable"), count, kind)
        }
        public static var netPosition: String { String(localized: "splits:netPosition", table: "Localizable") }
        public static var newGroupCta: String { String(localized: "splits:newGroupCta", table: "Localizable") }
        public static var noneMarkSettled: String { String(localized: "splits:noneMarkSettled", table: "Localizable") }
        public static var openGroup: String { String(localized: "splits:openGroup", table: "Localizable") }
        public static func owedInGroup(amount: String) -> String {
            String(format: String(localized: "splits:owedInGroup", table: "Localizable"), amount)
        }
        public static func oweInGroup(amount: String) -> String {
            String(format: String(localized: "splits:oweInGroup", table: "Localizable"), amount)
        }
        public static var owesYouInline: String { String(localized: "splits:owesYouInline", table: "Localizable") }
        public static var paidFrom: String { String(localized: "splits:paidFrom", table: "Localizable") }
        public static var payAnyoneCta: String { String(localized: "splits:payAnyoneCta", table: "Localizable") }
        public static var receivedInto: String { String(localized: "splits:receivedInto", table: "Localizable") }
        public static var remind: String { String(localized: "splits:remind", table: "Localizable") }
        public static func remindOwe(name: String, amount: String) -> String {
            String(format: String(localized: "splits:remindOwe", table: "Localizable"), name, amount)
        }
        public static func remindOwed(name: String, amount: String) -> String {
            String(format: String(localized: "splits:remindOwed", table: "Localizable"), name, amount)
        }
        public static var sectionsFriends: String { String(localized: "splits:sections.friends", table: "Localizable") }
        public static var sectionsGroupsAndTrips: String { String(localized: "splits:sections.groupsAndTrips", table: "Localizable") }
        public static var sectionsInsights: String { String(localized: "splits:sections.insights", table: "Localizable") }
        public static var sectionsOwesYou: String { String(localized: "splits:sections.owesYou", table: "Localizable") }
        public static var sectionsYouOwe: String { String(localized: "splits:sections.youOwe", table: "Localizable") }
        public static var settle: String { String(localized: "splits:settle", table: "Localizable") }
        public static var settledUp: String { String(localized: "splits:settledUp", table: "Localizable") }
        public static var settlementTag: String { String(localized: "splits:settlementTag", table: "Localizable") }
        public static var settleUp: String { String(localized: "splits:settleUp", table: "Localizable") }
        public static func settleWith(name: String) -> String {
            String(format: String(localized: "splits:settleWith", table: "Localizable"), name)
        }
        public static var settling: String { String(localized: "splits:settling", table: "Localizable") }
        public static func theyPayYouBack(name: String) -> String {
            String(format: String(localized: "splits:theyPayYouBack", table: "Localizable"), name)
        }
        public static var totalOwedToYou: String { String(localized: "splits:totalOwedToYou", table: "Localizable") }
        public static var totalYouOwe: String { String(localized: "splits:totalYouOwe", table: "Localizable") }
        public static func viewLines(count: Int) -> String {
            String(format: String(localized: "splits:viewLines", defaultValue: "", table: "Localizable"), count)
        }
        public static var youOweInline: String { String(localized: "splits:youOweInline", table: "Localizable") }
        public static func youPayThemBack(name: String) -> String {
            String(format: String(localized: "splits:youPayThemBack", table: "Localizable"), name)
        }
        public static var yourBalance: String { String(localized: "splits:yourBalance", table: "Localizable") }
    }

    public enum Statements {
        public static var analyze: String { String(localized: "statements:analyze", table: "Localizable") }
        public static var expenses: String { String(localized: "statements:expenses", table: "Localizable") }
        public static var fromDate: String { String(localized: "statements:fromDate", table: "Localizable") }
        public static var goPremium: String { String(localized: "statements:goPremium", table: "Localizable") }
        public static var income: String { String(localized: "statements:income", table: "Localizable") }
        public static var netForPeriod: String { String(localized: "statements:netForPeriod", table: "Localizable") }
        public static var noTransactions: String { String(localized: "statements:noTransactions", table: "Localizable") }
        public static var premiumBody: String { String(localized: "statements:premiumBody", table: "Localizable") }
        public static var premiumTitle: String { String(localized: "statements:premiumTitle", table: "Localizable") }
        public static var print: String { String(localized: "statements:print", table: "Localizable") }
        public static var statementName: String { String(localized: "statements:statementName", table: "Localizable") }
        public static var title: String { String(localized: "statements:title", table: "Localizable") }
        public static var toDate: String { String(localized: "statements:toDate", table: "Localizable") }
        public static var today: String { String(localized: "statements:today", table: "Localizable") }
        public static var transactions: String { String(localized: "statements:transactions", table: "Localizable") }
        public static var yesterday: String { String(localized: "statements:yesterday", table: "Localizable") }
    }

    public enum StatementsAnalyze {
        public static var accountToReconcile: String { String(localized: "statementsAnalyze:accountToReconcile", table: "Localizable") }
        public static var addAsRecurring: String { String(localized: "statementsAnalyze:addAsRecurring", table: "Localizable") }
        public static var added: String { String(localized: "statementsAnalyze:added", table: "Localizable") }
        public static var bank: String { String(localized: "statementsAnalyze:bank", table: "Localizable") }
        public static var cadenceMonthly: String { String(localized: "statementsAnalyze:cadence.monthly", table: "Localizable") }
        public static var cadenceWeekly: String { String(localized: "statementsAnalyze:cadence.weekly", table: "Localizable") }
        public static var cadenceYearly: String { String(localized: "statementsAnalyze:cadence.yearly", table: "Localizable") }
        public static var card: String { String(localized: "statementsAnalyze:card", table: "Localizable") }
        public static var categorising: String { String(localized: "statementsAnalyze:categorising", table: "Localizable") }
        public static var chooseFile: String { String(localized: "statementsAnalyze:chooseFile", table: "Localizable") }
        public static var chooseFileCsvOnly: String { String(localized: "statementsAnalyze:chooseFileCsvOnly", table: "Localizable") }
        public static var chooseLater: String { String(localized: "statementsAnalyze:chooseLater", table: "Localizable") }
        public static var closingBalance: String { String(localized: "statementsAnalyze:closingBalance", table: "Localizable") }
        public static var dailySpend: String { String(localized: "statementsAnalyze:dailySpend", table: "Localizable") }
        public static var importedDone: String { String(localized: "statementsAnalyze:importedDone", table: "Localizable") }
        public static func importMissing(count: String, account: String) -> String {
            String(format: String(localized: "statementsAnalyze:importMissing", table: "Localizable"), count, account)
        }
        public static var introBold: String { String(localized: "statementsAnalyze:introBold", table: "Localizable") }
        public static var introLink: String { String(localized: "statementsAnalyze:introLink", table: "Localizable") }
        public static var introMid: String { String(localized: "statementsAnalyze:introMid", table: "Localizable") }
        public static var introPost: String { String(localized: "statementsAnalyze:introPost", table: "Localizable") }
        public static var introPre: String { String(localized: "statementsAnalyze:introPre", table: "Localizable") }
        public static var looksRecurring: String { String(localized: "statementsAnalyze:looksRecurring", table: "Localizable") }
        public static var matchedLabel: String { String(localized: "statementsAnalyze:matchedLabel", table: "Localizable") }
        public static var minimumDue: String { String(localized: "statementsAnalyze:minimumDue", table: "Localizable") }
        public static var missingLabel: String { String(localized: "statementsAnalyze:missingLabel", table: "Localizable") }
        public static var moneyIn: String { String(localized: "statementsAnalyze:moneyIn", table: "Localizable") }
        public static var moneyOut: String { String(localized: "statementsAnalyze:moneyOut", table: "Localizable") }
        public static var net: String { String(localized: "statementsAnalyze:net", table: "Localizable") }
        public static var newStatement: String { String(localized: "statementsAnalyze:newStatement", table: "Localizable") }
        public static var noSpends: String { String(localized: "statementsAnalyze:noSpends", table: "Localizable") }
        public static var onlyPlatformLabel: String { String(localized: "statementsAnalyze:onlyPlatformLabel", table: "Localizable") }
        public static var outliersTitle: String { String(localized: "statementsAnalyze:outliersTitle", table: "Localizable") }
        public static var parsing: String { String(localized: "statementsAnalyze:parsing", table: "Localizable") }
        public static var payBy: String { String(localized: "statementsAnalyze:payBy", table: "Localizable") }
        public static var pdfCancel: String { String(localized: "statementsAnalyze:pdfCancel", table: "Localizable") }
        public static var pdfPassword: String { String(localized: "statementsAnalyze:pdfPassword", table: "Localizable") }
        public static var pdfUnavailable: String { String(localized: "statementsAnalyze:pdfUnavailable", table: "Localizable") }
        public static var pdfUnlock: String { String(localized: "statementsAnalyze:pdfUnlock", table: "Localizable") }
        public static var pickAccountReconcile: String { String(localized: "statementsAnalyze:pickAccountReconcile", table: "Localizable") }
        public static var readFail: String { String(localized: "statementsAnalyze:readFail", table: "Localizable") }
        public static var readingPdf: String { String(localized: "statementsAnalyze:readingPdf", table: "Localizable") }
        public static var reconcileTitle: String { String(localized: "statementsAnalyze:reconcileTitle", table: "Localizable") }
        public static func recurringMeta(amount: String, cadence: String, count: String) -> String {
            String(format: String(localized: "statementsAnalyze:recurringMeta", table: "Localizable"), amount, cadence, count)
        }
        public static func showAll(count: String) -> String {
            String(format: String(localized: "statementsAnalyze:showAll", table: "Localizable"), count)
        }
        public static var showLess: String { String(localized: "statementsAnalyze:showLess", table: "Localizable") }
        public static var statementType: String { String(localized: "statementsAnalyze:statementType", table: "Localizable") }
        public static var tipBold: String { String(localized: "statementsAnalyze:tipBold", table: "Localizable") }
        public static var tipPost: String { String(localized: "statementsAnalyze:tipPost", table: "Localizable") }
        public static var tipPre: String { String(localized: "statementsAnalyze:tipPre", table: "Localizable") }
        public static var title: String { String(localized: "statementsAnalyze:title", table: "Localizable") }
        public static var totalDue: String { String(localized: "statementsAnalyze:totalDue", table: "Localizable") }
        public static func transactions(count: String) -> String {
            String(format: String(localized: "statementsAnalyze:transactions", table: "Localizable"), count)
        }
        public static func transactionsTitle(count: String) -> String {
            String(format: String(localized: "statementsAnalyze:transactionsTitle", table: "Localizable"), count)
        }
        public static var whereItWent: String { String(localized: "statementsAnalyze:whereItWent", table: "Localizable") }
    }

    public enum Templates {
        public static var account: String { String(localized: "templates:account", table: "Localizable") }
        public static func actions(name: String) -> String {
            String(format: String(localized: "templates:actions", table: "Localizable"), name)
        }
        public static func amountPlaceholder(base: String) -> String {
            String(format: String(localized: "templates:amountPlaceholder", table: "Localizable"), base)
        }
        public static var cancel: String { String(localized: "templates:cancel", table: "Localizable") }
        public static var chooseAtUse: String { String(localized: "templates:chooseAtUse", table: "Localizable") }
        public static var create: String { String(localized: "templates:create", table: "Localizable") }
        public static var delete: String { String(localized: "templates:delete", table: "Localizable") }
        public static func deleteMsg(name: String) -> String {
            String(format: String(localized: "templates:deleteMsg", table: "Localizable"), name)
        }
        public static var deleteTitle: String { String(localized: "templates:deleteTitle", table: "Localizable") }
        public static var descriptionPlaceholder: String { String(localized: "templates:descriptionPlaceholder", table: "Localizable") }
        public static var edit: String { String(localized: "templates:edit", table: "Localizable") }
        public static var editTitle: String { String(localized: "templates:editTitle", table: "Localizable") }
        public static func freeUsed(used: String, limit: String) -> String {
            String(format: String(localized: "templates:freeUsed", table: "Localizable"), used, limit)
        }
        public static var goPremium: String { String(localized: "templates:goPremium", table: "Localizable") }
        public static var introLink: String { String(localized: "templates:introLink", table: "Localizable") }
        public static var introPre: String { String(localized: "templates:introPre", table: "Localizable") }
        public static func limitMsg(limit: String) -> String {
            String(format: String(localized: "templates:limitMsg", table: "Localizable"), limit)
        }
        public static var limitTitle: String { String(localized: "templates:limitTitle", table: "Localizable") }
        public static var namePlaceholder: String { String(localized: "templates:namePlaceholder", table: "Localizable") }
        public static var newTemplate: String { String(localized: "templates:newTemplate", table: "Localizable") }
        public static var newTitle: String { String(localized: "templates:newTitle", table: "Localizable") }
        public static var noTemplates: String { String(localized: "templates:noTemplates", table: "Localizable") }
        public static var save: String { String(localized: "templates:save", table: "Localizable") }
        public static var split: String { String(localized: "templates:split", table: "Localizable") }
        public static var title: String { String(localized: "templates:title", table: "Localizable") }
        public static var typeExpense: String { String(localized: "templates:type.expense", table: "Localizable") }
        public static var typeIncome: String { String(localized: "templates:type.income", table: "Localizable") }
        public static var use: String { String(localized: "templates:use", table: "Localizable") }
    }

    public enum Transactions {
        public static var account: String { String(localized: "transactions:account", table: "Localizable") }
        public static var add: String { String(localized: "transactions:add", table: "Localizable") }
        public static var addItemSplit: String { String(localized: "transactions:addItemSplit", table: "Localizable") }
        public static var addTitle: String { String(localized: "transactions:addTitle", table: "Localizable") }
        public static var amount: String { String(localized: "transactions:amount", table: "Localizable") }
        public static func amountCurrency(currency: String) -> String {
            String(format: String(localized: "transactions:amountCurrency", table: "Localizable"), currency)
        }
        public static func amountReceived(currency: String) -> String {
            String(format: String(localized: "transactions:amountReceived", table: "Localizable"), currency)
        }
        public static var amountWithItems: String { String(localized: "transactions:amountWithItems", table: "Localizable") }
        public static var auditAccountId: String { String(localized: "transactions:audit.account_id", table: "Localizable") }
        public static var auditAmount: String { String(localized: "transactions:audit.amount", table: "Localizable") }
        public static var auditCategoryId: String { String(localized: "transactions:audit.category_id", table: "Localizable") }
        public static var auditDescription: String { String(localized: "transactions:audit.description", table: "Localizable") }
        public static var auditMerchant: String { String(localized: "transactions:audit.merchant", table: "Localizable") }
        public static var auditNote: String { String(localized: "transactions:audit.note", table: "Localizable") }
        public static var auditOccurredAt: String { String(localized: "transactions:audit.occurred_at", table: "Localizable") }
        public static var auditPaymentMethodId: String { String(localized: "transactions:audit.payment_method_id", table: "Localizable") }
        public static var auditToAccountId: String { String(localized: "transactions:audit.to_account_id", table: "Localizable") }
        public static var auditToAmount: String { String(localized: "transactions:audit.to_amount", table: "Localizable") }
        public static var auditType: String { String(localized: "transactions:audit.type", table: "Localizable") }
        public static var autoCategorised: String { String(localized: "transactions:autoCategorised", table: "Localizable") }
        public static func autoSplitWith(name: String) -> String {
            String(format: String(localized: "transactions:autoSplitWith", table: "Localizable"), name)
        }
        public static var cancel: String { String(localized: "transactions:cancel", table: "Localizable") }
        public static var category: String { String(localized: "transactions:category", table: "Localizable") }
        public static var chooseGroup: String { String(localized: "transactions:chooseGroup", table: "Localizable") }
        public static var countsInBudget: String { String(localized: "transactions:countsInBudget", table: "Localizable") }
        public static var createAccountFirst: String { String(localized: "transactions:createAccountFirst", table: "Localizable") }
        public static var date: String { String(localized: "transactions:date", table: "Localizable") }
        public static var defaultExpense: String { String(localized: "transactions:defaultExpense", table: "Localizable") }
        public static var defaultIncome: String { String(localized: "transactions:defaultIncome", table: "Localizable") }
        public static var defaultTransfer: String { String(localized: "transactions:defaultTransfer", table: "Localizable") }
        public static var delete: String { String(localized: "transactions:delete", table: "Localizable") }
        public static var deleteConfirmMsg: String { String(localized: "transactions:deleteConfirmMsg", table: "Localizable") }
        public static var deleteConfirmTitle: String { String(localized: "transactions:deleteConfirmTitle", table: "Localizable") }
        public static var editHistory: String { String(localized: "transactions:editHistory", table: "Localizable") }
        public static var editTitle: String { String(localized: "transactions:editTitle", table: "Localizable") }
        public static var extraNotes: String { String(localized: "transactions:extraNotes", table: "Localizable") }
        public static var filterAll: String { String(localized: "transactions:filter.all", table: "Localizable") }
        public static var filterExpense: String { String(localized: "transactions:filter.expense", table: "Localizable") }
        public static var filterIncome: String { String(localized: "transactions:filter.income", table: "Localizable") }
        public static var filterTransfer: String { String(localized: "transactions:filter.transfer", table: "Localizable") }
        public static var findingCategory: String { String(localized: "transactions:findingCategory", table: "Localizable") }
        public static var fromAccount: String { String(localized: "transactions:fromAccount", table: "Localizable") }
        public static var groupTrip: String { String(localized: "transactions:groupTrip", table: "Localizable") }
        public static var investmentBlocked: String { String(localized: "transactions:investmentBlocked", table: "Localizable") }
        public static var investmentTransferOnly: String { String(localized: "transactions:investmentTransferOnly", table: "Localizable") }
        public static func item(n: String) -> String {
            String(format: String(localized: "transactions:item", table: "Localizable"), n)
        }
        public static var labels: String { String(localized: "transactions:labels", table: "Localizable") }
        public static var labelsOptional: String { String(localized: "transactions:labelsOptional", table: "Localizable") }
        public static var loading: String { String(localized: "transactions:loading", table: "Localizable") }
        public static func memberPaid(name: String) -> String {
            String(format: String(localized: "transactions:memberPaid", table: "Localizable"), name)
        }
        public static var minorUpdate: String { String(localized: "transactions:minorUpdate", table: "Localizable") }
        public static var modeEqual: String { String(localized: "transactions:mode.equal", table: "Localizable") }
        public static var modeExact: String { String(localized: "transactions:mode.exact", table: "Localizable") }
        public static var modePercent: String { String(localized: "transactions:mode.percent", table: "Localizable") }
        public static var multiplePaid: String { String(localized: "transactions:multiplePaid", table: "Localizable") }
        public static var newAccountCta: String { String(localized: "transactions:newAccountCta", table: "Localizable") }
        public static var noEdits: String { String(localized: "transactions:noEdits", table: "Localizable") }
        public static var noMatching: String { String(localized: "transactions:noMatching", table: "Localizable") }
        public static var note: String { String(localized: "transactions:note", table: "Localizable") }
        public static var noteOptional: String { String(localized: "transactions:noteOptional", table: "Localizable") }
        public static var onlyYou: String { String(localized: "transactions:onlyYou", table: "Localizable") }
        public static func onlyYourPayment(account: String) -> String {
            String(format: String(localized: "transactions:onlyYourPayment", table: "Localizable"), account)
        }
        public static var optionalNote: String { String(localized: "transactions:optionalNote", table: "Localizable") }
        public static func othersOweYou(amount: String) -> String {
            String(format: String(localized: "transactions:othersOweYou", table: "Localizable"), amount)
        }
        public static func paidMatch(sum: String, total: String) -> String {
            String(format: String(localized: "transactions:paidMatch", table: "Localizable"), sum, total)
        }
        public static func paidMismatch(sum: String, total: String) -> String {
            String(format: String(localized: "transactions:paidMismatch", table: "Localizable"), sum, total)
        }
        public static var paymentMethod: String { String(localized: "transactions:paymentMethod", table: "Localizable") }
        public static func percentMatch(pct: String) -> String {
            String(format: String(localized: "transactions:percentMatch", table: "Localizable"), pct)
        }
        public static func percentMismatch(pct: String) -> String {
            String(format: String(localized: "transactions:percentMismatch", table: "Localizable"), pct)
        }
        public static var pickGroupLink: String { String(localized: "transactions:pickGroupLink", table: "Localizable") }
        public static var pickGroupPre: String { String(localized: "transactions:pickGroupPre", table: "Localizable") }
        public static var pickTwo: String { String(localized: "transactions:pickTwo", table: "Localizable") }
        public static var remove: String { String(localized: "transactions:remove", table: "Localizable") }
        public static var saveAsTemplate: String { String(localized: "transactions:saveAsTemplate", table: "Localizable") }
        public static var saveChanges: String { String(localized: "transactions:saveChanges", table: "Localizable") }
        public static var saveChangesError: String { String(localized: "transactions:saveChangesError", table: "Localizable") }
        public static var savedAsTemplate: String { String(localized: "transactions:savedAsTemplate", table: "Localizable") }
        public static var saveError: String { String(localized: "transactions:saveError", table: "Localizable") }
        public static func saveWithTotal(total: String) -> String {
            String(format: String(localized: "transactions:saveWithTotal", table: "Localizable"), total)
        }
        public static var saving: String { String(localized: "transactions:saving", table: "Localizable") }
        public static var searchCategory: String { String(localized: "transactions:searchCategory", table: "Localizable") }
        public static var searchPlaceholder: String { String(localized: "transactions:searchPlaceholder", table: "Localizable") }
        public static func sharesMatch(sum: String, total: String) -> String {
            String(format: String(localized: "transactions:sharesMatch", table: "Localizable"), sum, total)
        }
        public static func sharesMismatch(sum: String, total: String) -> String {
            String(format: String(localized: "transactions:sharesMismatch", table: "Localizable"), sum, total)
        }
        public static var someone: String { String(localized: "transactions:someone", table: "Localizable") }
        public static var splitBetween: String { String(localized: "transactions:splitBetween", table: "Localizable") }
        public static var splitChip: String { String(localized: "transactions:splitChip", table: "Localizable") }
        public static var splitExpense: String { String(localized: "transactions:splitExpense", table: "Localizable") }
        public static var startFromTemplate: String { String(localized: "transactions:startFromTemplate", table: "Localizable") }
        public static func templateLimitMsg(limit: String) -> String {
            String(format: String(localized: "transactions:templateLimitMsg", table: "Localizable"), limit)
        }
        public static var templateLimitTitle: String { String(localized: "transactions:templateLimitTitle", table: "Localizable") }
        public static var templateNamePrompt: String { String(localized: "transactions:templateNamePrompt", table: "Localizable") }
        public static var title: String { String(localized: "transactions:title", table: "Localizable") }
        public static var toAccount: String { String(localized: "transactions:toAccount", table: "Localizable") }
        public static var txOptions: String { String(localized: "transactions:txOptions", table: "Localizable") }
        public static var typeExpense: String { String(localized: "transactions:type.expense", table: "Localizable") }
        public static var typeIncome: String { String(localized: "transactions:type.income", table: "Localizable") }
        public static var typeTransfer: String { String(localized: "transactions:type.transfer", table: "Localizable") }
        public static var uncategorised: String { String(localized: "transactions:uncategorised", table: "Localizable") }
        public static var viewHistory: String { String(localized: "transactions:viewHistory", table: "Localizable") }
        public static var whatFor: String { String(localized: "transactions:whatFor", table: "Localizable") }
        public static var you: String { String(localized: "transactions:you", table: "Localizable") }
        public static func youllOwe(amount: String) -> String {
            String(format: String(localized: "transactions:youllOwe", table: "Localizable"), amount)
        }
        public static func youPaidFrom(total: String, account: String) -> String {
            String(format: String(localized: "transactions:youPaidFrom", table: "Localizable"), total, account)
        }
        public static var yourShare: String { String(localized: "transactions:yourShare", table: "Localizable") }
    }

    public enum Translation {
        public static var accountTypeCash: String { String(localized: "translation:accountType.cash", table: "Localizable") }
        public static var accountTypeCreditCard: String { String(localized: "translation:accountType.credit_card", table: "Localizable") }
        public static var accountTypeCurrent: String { String(localized: "translation:accountType.current", table: "Localizable") }
        public static var accountTypeMutualFunds: String { String(localized: "translation:accountType.mutual_funds", table: "Localizable") }
        public static var accountTypeSavings: String { String(localized: "translation:accountType.savings", table: "Localizable") }
        public static var accountTypeStocks: String { String(localized: "translation:accountType.stocks", table: "Localizable") }
        public static var appName: String { String(localized: "translation:app.name", table: "Localizable") }
        public static var commonAdd: String { String(localized: "translation:common.add", table: "Localizable") }
        public static var commonAdding: String { String(localized: "translation:common.adding", table: "Localizable") }
        public static var commonBack: String { String(localized: "translation:common.back", table: "Localizable") }
        public static var commonCancel: String { String(localized: "translation:common.cancel", table: "Localizable") }
        public static var commonClear: String { String(localized: "translation:common.clear", table: "Localizable") }
        public static var commonClose: String { String(localized: "translation:common.close", table: "Localizable") }
        public static var commonDelete: String { String(localized: "translation:common.delete", table: "Localizable") }
        public static var commonDone: String { String(localized: "translation:common.done", table: "Localizable") }
        public static var commonEdit: String { String(localized: "translation:common.edit", table: "Localizable") }
        public static var commonRemove: String { String(localized: "translation:common.remove", table: "Localizable") }
        public static var commonSave: String { String(localized: "translation:common.save", table: "Localizable") }
        public static var commonSaveChanges: String { String(localized: "translation:common.saveChanges", table: "Localizable") }
        public static var commonSaving: String { String(localized: "translation:common.saving", table: "Localizable") }
        public static var commonSettings: String { String(localized: "translation:common.settings", table: "Localizable") }
        public static var fabAdd: String { String(localized: "translation:fab.add", table: "Localizable") }
        public static var fabAddTransaction: String { String(localized: "translation:fab.addTransaction", table: "Localizable") }
        public static var fabClose: String { String(localized: "translation:fab.close", table: "Localizable") }
        public static var fabScanReceipt: String { String(localized: "translation:fab.scanReceipt", table: "Localizable") }
        public static var navAccounts: String { String(localized: "translation:nav.accounts", table: "Localizable") }
        public static var navAssistant: String { String(localized: "translation:nav.assistant", table: "Localizable") }
        public static var navBudgets: String { String(localized: "translation:nav.budgets", table: "Localizable") }
        public static var navCards: String { String(localized: "translation:nav.cards", table: "Localizable") }
        public static var navCustomize: String { String(localized: "translation:nav.customize", table: "Localizable") }
        public static func navCustomizeHint(n: String) -> String {
            String(format: String(localized: "translation:nav.customizeHint", table: "Localizable"), n)
        }
        public static var navFriends: String { String(localized: "translation:nav.friends", table: "Localizable") }
        public static var navGoals: String { String(localized: "translation:nav.goals", table: "Localizable") }
        public static var navHelp: String { String(localized: "translation:nav.help", table: "Localizable") }
        public static var navHome: String { String(localized: "translation:nav.home", table: "Localizable") }
        public static var navInsights: String { String(localized: "translation:nav.insights", table: "Localizable") }
        public static var navInvestments: String { String(localized: "translation:nav.investments", table: "Localizable") }
        public static var navLoans: String { String(localized: "translation:nav.loans", table: "Localizable") }
        public static var navMore: String { String(localized: "translation:nav.more", table: "Localizable") }
        public static var navNotifications: String { String(localized: "translation:nav.notifications", table: "Localizable") }
        public static var navRecurring: String { String(localized: "translation:nav.recurring", table: "Localizable") }
        public static var navReflect: String { String(localized: "translation:nav.reflect", table: "Localizable") }
        public static var navSearch: String { String(localized: "translation:nav.search", table: "Localizable") }
        public static var navSettings: String { String(localized: "translation:nav.settings", table: "Localizable") }
        public static var navStatements: String { String(localized: "translation:nav.statements", table: "Localizable") }
        public static var navSubscriptions: String { String(localized: "translation:nav.subscriptions", table: "Localizable") }
        public static var navTransactions: String { String(localized: "translation:nav.transactions", table: "Localizable") }
        public static var netWorthAvailable: String { String(localized: "translation:netWorth.available", table: "Localizable") }
        public static var netWorthTitle: String { String(localized: "translation:netWorth.title", table: "Localizable") }
        public static var netWorthWithBlocked: String { String(localized: "translation:netWorth.withBlocked", table: "Localizable") }
        public static var onboardingGetStarted: String { String(localized: "translation:onboarding.getStarted", table: "Localizable") }
        public static func onboardingGuestBanner(days: String) -> String {
            String(format: String(localized: "translation:onboarding.guestBanner", table: "Localizable"), days)
        }
        public static var pagesAccounts: String { String(localized: "translation:pages.accounts", table: "Localizable") }
        public static var pagesBudgets: String { String(localized: "translation:pages.budgets", table: "Localizable") }
        public static var pagesCards: String { String(localized: "translation:pages.cards", table: "Localizable") }
        public static var pagesDashboard: String { String(localized: "translation:pages.dashboard", table: "Localizable") }
        public static var pagesGoals: String { String(localized: "translation:pages.goals", table: "Localizable") }
        public static var pagesInsights: String { String(localized: "translation:pages.insights", table: "Localizable") }
        public static var pagesInvestments: String { String(localized: "translation:pages.investments", table: "Localizable") }
        public static var pagesLoans: String { String(localized: "translation:pages.loans", table: "Localizable") }
        public static var pagesSearch: String { String(localized: "translation:pages.search", table: "Localizable") }
        public static var pagesSettings: String { String(localized: "translation:pages.settings", table: "Localizable") }
        public static var pagesStatements: String { String(localized: "translation:pages.statements", table: "Localizable") }
        public static var pagesSubscriptions: String { String(localized: "translation:pages.subscriptions", table: "Localizable") }
        public static var pagesTransactions: String { String(localized: "translation:pages.transactions", table: "Localizable") }
        public static var settingsAccount: String { String(localized: "translation:settings.account", table: "Localizable") }
        public static var settingsAppearance: String { String(localized: "translation:settings.appearance", table: "Localizable") }
        public static var settingsBaseCurrency: String { String(localized: "translation:settings.baseCurrency", table: "Localizable") }
        public static var settingsDark: String { String(localized: "translation:settings.dark", table: "Localizable") }
        public static var settingsHelp: String { String(localized: "translation:settings.help", table: "Localizable") }
        public static var settingsHideAmounts: String { String(localized: "translation:settings.hideAmounts", table: "Localizable") }
        public static var settingsLanguage: String { String(localized: "translation:settings.language", table: "Localizable") }
        public static var settingsLight: String { String(localized: "translation:settings.light", table: "Localizable") }
        public static var settingsPlan: String { String(localized: "translation:settings.plan", table: "Localizable") }
        public static var settingsPrivacy: String { String(localized: "translation:settings.privacy", table: "Localizable") }
        public static var transactionAddItem: String { String(localized: "translation:transaction.addItem", table: "Localizable") }
        public static var transactionAmount: String { String(localized: "translation:transaction.amount", table: "Localizable") }
        public static var transactionCategory: String { String(localized: "translation:transaction.category", table: "Localizable") }
        public static var transactionExpense: String { String(localized: "translation:transaction.expense", table: "Localizable") }
        public static var transactionIncome: String { String(localized: "translation:transaction.income", table: "Localizable") }
        public static var transactionLabel: String { String(localized: "translation:transaction.label", table: "Localizable") }
        public static var transactionTransfer: String { String(localized: "translation:transaction.transfer", table: "Localizable") }
    }
}
