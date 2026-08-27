import Data
import Domain
import Factory
import Foundation

/// One bubble in the transcript. `role` is "user" | "assistant" | "action".
struct ChatBubble: Identifiable, Equatable {
    let id: String
    let role: String
    let text: String
}

/**
 The assistant chat.

 Ported from `apps/web/src/assistant/AssistantChat.tsx`. The DECISIONS live in
 Domain and are vector-pinned — which tools run silently, which are refused, how
 the history window is trimmed, what the confirm card says. This holds the
 screen's state and drives the loop.

 **The turn loop recurses.** A model turn can end in tool calls; running them
 produces `tool_result` blocks which are sent back as a new user turn, and the
 model answers again. Web recurses through `runTurn`; so does this. The chain
 only stops when a turn comes back with no tool calls, or when one is waiting on
 the user.

 Mirrors Android's AssistantViewModel.kt.
 */
@Observable
@MainActor
final class AssistantViewModel {
    @ObservationIgnored
    @Injected(\.assistantRepository) private var assistantRepository
    @ObservationIgnored
    @Injected(\.authRepository) private var authRepository
    @ObservationIgnored
    @Injected(\.prefsRepository) private var prefsRepository

    // ---- screen state ----

    /// Web's own two views.
    enum ViewState { case landing, chat }

    private(set) var view: ViewState = .landing
    private(set) var bubbles: [ChatBubble] = []
    private(set) var busy = false
    /// The confirmation card currently on screen, or nil.
    private(set) var pendingTool: ToolUse?
    private(set) var quota: EntitlementQuota?
    private(set) var isPaid = false
    /// True once the entitlement has been read at all, so the gate does not flash.
    private(set) var entitlementKnown = false
    /// The exact context string sent to the model, for the "view data" panel.
    private(set) var payload: String?
    private(set) var threads: [AssistantThread] = []

    var isOutOfQuota: Bool { (quota?.left ?? 1) <= 0 }

    // ---- the model conversation, which is NOT the transcript ----

    /**
     What the model sees. Deliberately separate from `bubbles`.

     The transcript is prose; this carries `tool_use` and `tool_result` blocks
     that are never persisted and never shown. Rebuilding one from the other is
     lossy in both directions, which is why web keeps two and so does this.
     */
    private var conversation: [ApiMessage] = []
    private var systemBlocks: [String] = [assistantPersona]
    private var threadId: String?
    private var pendingRest: [ToolUse] = []
    private var pendingResults: [AssistantContent] = []
    private var pendingMessages: [ApiMessage] = []
    private var bubbleCounter = 0
    private var tasks: [Task<Void, Never>] = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        tasks.append(Task { [weak self] in
            guard let self else { return }
            do {
                for try await row in try self.prefsRepository.watchEntitlement() {
                    let state = entitlementState(
                        tier: row?.tier,
                        premiumTrialStartDate: row?.premiumTrialStartDate,
                        compTier: row?.compTier,
                        compUntil: row?.compUntil,
                        nowMillis: Int64(Date().timeIntervalSince1970 * 1000),
                        monthlyQuotaTotal: row?.monthlyQuotaTotal,
                        monthlyQuotaUsed: row?.monthlyQuotaUsed,
                        purchasedQuotaRemaining: row?.purchasedQuotaRemaining,
                        additionalPurchasedQuota: row?.additionalPurchasedQuota
                    )
                    self.isPaid = state.isPaid
                    self.quota = EntitlementQuota(
                        planLeft: max(0, state.quotaTotal - state.quotaUsed),
                        total: state.quotaTotal,
                        purchased: state.purchased,
                        left: state.quotaLeft,
                        resetDate: row?.quotaResetDate
                    )
                    self.entitlementKnown = true
                }
            } catch {
                print("Assistant: failed to watch entitlement: \(error)")
                self.entitlementKnown = true
            }
        })
        tasks.append(Task { [weak self] in
            guard let self, let userId = await self.resolveUserId() else { return }
            do {
                for try await rows in try self.assistantRepository.watchThreads(userId: userId) {
                    self.threads = rows
                }
            } catch { print("Assistant: failed to watch threads: \(error)") }
        })
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks = []
    }

    // ---- navigation between the landing and a chat ----

    func newChat(greeting: String) {
        conversation = []
        threadId = nil
        clearPending()
        // Local-only greeting: not persisted, not sent to the model. Web says
        // the same in its own comment, and it matters — a greeting in the
        // model's context would be an assistant turn with nothing before it.
        bubbles = [bubble(role: "assistant", text: greeting)]
        view = .chat
    }

    func openThread(id: String) {
        clearPending()
        threadId = id
        view = .chat
        Task { [weak self] in
            guard let self else { return }
            let rows = (try? await self.assistantRepository.messagesOnce(threadId: id)) ?? []
            self.bubbles = rows.map { ChatBubble(id: $0.id, role: $0.role, text: $0.content) }
            // Rebuild the model's context from the TEXT transcript. Tool blocks
            // were never persisted, so a reopened thread has no memory of the
            // calls it made — web accepts the same loss.
            self.conversation = rows
                .filter { $0.role == "user" || $0.role == "assistant" }
                .map { ApiMessage(role: $0.role, textContent: $0.content) }
        }
    }

    func backToLanding() { view = .landing }

    func deleteThread(id: String) {
        Task { [weak self] in
            try? await self?.assistantRepository.deleteThread(threadId: id)
        }
    }

    // ---- sending ----

    /**
     Send a message.

     The snapshot and the remembered facts are rebuilt on EVERY send, not
     cached: the user may have added a transaction between two questions, and an
     assistant answering from a stale balance is worse than a slow one.
     */
    func send(_ raw: String, errorText: @escaping (String, String) -> String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy, pendingTool == nil, !isOutOfQuota else { return }

        bubbles.append(bubble(role: "user", text: text))
        view = .chat

        Task { [weak self] in
            guard let self, let userId = await self.resolveUserId() else { return }
            let base = baseCurrencyNow()
            let context = await self.buildContext(userId: userId, baseCurrency: base)

            self.payload = context
            // On failure the persona still goes — an assistant with no snapshot
            // can still explain the app, and web degrades the same way.
            self.systemBlocks = context.map { [assistantPersona, $0] } ?? [assistantPersona]

            if self.threadId == nil {
                self.threadId = try? await self.assistantRepository.createThread(
                    userId: userId,
                    title: assistantThreadTitle(text)
                )
            }
            if let threadId = self.threadId {
                _ = try? await self.assistantRepository.appendMessage(
                    userId: userId, threadId: threadId, role: "user", content: text
                )
            }

            self.conversation.append(ApiMessage(role: "user", textContent: text))
            await self.runTurn(self.conversation, userId: userId, baseCurrency: base, errorText: errorText)
        }
    }

    private func buildContext(userId: String, baseCurrency: String) async -> String? {
        do {
            let today = plainDayUtc(Date())
            let summary = try await assistantRepository.buildFinancialSummary(
                userId: userId,
                baseCurrency: baseCurrency,
                todayIso: today,
                now: Date()
            )
            let memory = (try? await assistantRepository.loadMemory(userId: userId)) ?? ""
            return [
                "Today: \(summary.today). Base currency: \(summary.baseCurrency).",
                "User's aggregated financial snapshot (the only financial data you have):",
                summaryForPrompt(summary),
                "",
                "What you remember about this user:",
                memory.isEmpty ? "Nothing yet." : memory,
            ].joined(separator: "\n")
        } catch {
            return nil
        }
    }

    /**
     One round trip, plus whatever it leads to.

     Recursive, like web's. A turn that ends in auto-runnable tools sends their
     results straight back; a turn that ends in a confirmable one stops here and
     waits for `resolvePending`.
     */
    private func runTurn(
        _ messages: [ApiMessage],
        userId: String,
        baseCurrency: String,
        errorText: @escaping (String, String) -> String
    ) async {
        busy = true
        let response = await assistantRepository.callModel(systemBlocks: systemBlocks, messages: messages)
        busy = false

        guard let content = response.content else {
            let message = errorText(assistantErrorKey(response.error), response.error ?? "")
            bubbles.append(bubble(role: "assistant", text: message))
            return
        }

        let withAssistant = messages + [ApiMessage(role: "assistant", blocks: content)]
        conversation = withAssistant

        let plan = planAssistantTurn(content)
        if !plan.text.isEmpty {
            bubbles.append(bubble(role: "assistant", text: plan.text))
            if let threadId {
                _ = try? await assistantRepository.appendMessage(
                    userId: userId, threadId: threadId, role: "assistant", content: plan.text
                )
            }
        }

        var results: [AssistantContent] = []
        for tool in plan.autoRun {
            let result: String
            do {
                result = try await assistantRepository.executeTool(
                    userId: userId, name: tool.name, input: tool.input, baseCurrency: baseCurrency
                )
            } catch {
                result = "Error: \(error.localizedDescription)"
            }
            results.append(.result(toolUseId: tool.id, content: result))
        }
        for tool in plan.rejected {
            results.append(.result(toolUseId: tool.id, content: assistantToolRejected))
        }

        if plan.confirmQueue.isEmpty {
            if results.isEmpty { return }
            let next = withAssistant + [ApiMessage(role: "user", blocks: results)]
            conversation = next
            await runTurn(next, userId: userId, baseCurrency: baseCurrency, errorText: errorText)
        } else {
            pendingMessages = withAssistant
            pendingResults = results
            pendingRest = Array(plan.confirmQueue.dropFirst())
            pendingTool = plan.confirmQueue[0]
        }
    }

    /// Confirm or skip the card on screen, then continue the chain.
    func resolvePending(confirmed: Bool, errorText: @escaping (String, String) -> String) {
        guard let tool = pendingTool else { return }
        pendingTool = nil
        let baseCurrency = baseCurrencyNow()

        Task { [weak self] in
            guard let self, let userId = await self.resolveUserId() else { return }
            var result = assistantToolDeclined
            if confirmed {
                do {
                    result = try await self.assistantRepository.executeTool(
                        userId: userId, name: tool.name, input: tool.input, baseCurrency: baseCurrency
                    )
                } catch {
                    result = "Error: \(error.localizedDescription)"
                }
            }
            let note = assistantActionNote(
                tool.name, tool.input, baseCurrency: baseCurrency, confirmed: confirmed
            )
            self.bubbles.append(self.bubble(role: "action", text: note))
            if let threadId = self.threadId {
                _ = try? await self.assistantRepository.appendMessage(
                    userId: userId, threadId: threadId, role: "action", content: note
                )
            }

            self.pendingResults.append(.result(toolUseId: tool.id, content: result))
            if self.pendingRest.isEmpty {
                let next = self.pendingMessages + [ApiMessage(role: "user", blocks: self.pendingResults)]
                self.conversation = next
                self.clearPending()
                await self.runTurn(next, userId: userId, baseCurrency: baseCurrency, errorText: errorText)
            } else {
                self.pendingTool = self.pendingRest[0]
                self.pendingRest = Array(self.pendingRest.dropFirst())
            }
        }
    }

    /// The one-line summary on the confirmation card.
    func describePending(_ tool: ToolUse) -> String {
        describeToolCall(tool.name, tool.input, baseCurrency: baseCurrencyNow())
    }

    /// See GoalsViewModel.swift's identical helper — `??`'s RHS is an
    /// `@autoclosure`, so `currentUserId ?? (try? await ensureUser())` is
    /// invalid Swift; use an explicit if/else instead.
    private func resolveUserId() async -> String? {
        if let existing = authRepository.currentUserId { return existing }
        return try? await authRepository.ensureUser()
    }

    private func clearPending() {
        pendingTool = nil
        pendingRest = []
        pendingResults = []
        pendingMessages = []
    }

    private func bubble(role: String, text: String) -> ChatBubble {
        bubbleCounter += 1
        return ChatBubble(id: "b\(bubbleCounter)", role: role, text: text)
    }
}

/**
 Today as `YYYY-MM-DD` in UTC — the shape every date column in this product uses.

 A fresh formatter per call, not a cached `static let`. `ISO8601DateFormatter`
 is a mutable class and is not `Sendable`, so a static instance is a data race
 under Swift 6 strict concurrency and fails the build outright. The same
 reasoning is already written down in `Domain/Entitlements.swift`; this is the
 second place to learn it.
 */
private func plainDayUtc(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.string(from: date)
}
