import Foundation

@MainActor
extension ChatStore {
    func localIntentExecutionEnvironment() -> ChatLocalIntentExecutor.Environment {
        ChatLocalIntentExecutor.Environment(
            memoryStore: memoryStore,
            activityLog: activityLog,
            trackers: { [weak self] in self?.trackersProvider?() ?? [] },
            createTracker: { [weak self] briefing in self?.onCreateTracker?(briefing) },
            setPassiveMemoryEnabled: { [weak self] enabled in self?.passiveMemoryEnabled = enabled },
            setKeepDocumentsOnDevice: { [weak self] onDevice in self?.keepDocumentsOnDevice = onDevice },
            searchHistory: { [weak self] query in
                guard let self else { return [] }
                return ConversationHistorySearch.search(
                    query: query,
                    cache: self.loadLocalMessageCache(),
                    conversations: self.conversations
                )
            },
            scheduleReminder: { reminder in
                BriefingStore.schedulePersonalReminder(title: reminder.title, date: reminder.date)
            }
        )
    }

    /// Handles explicit app-control prompts locally, such as creating trackers,
    /// saving memory, or showing the user's current tracker digest.
    func handleQuickIntent(_ intent: QuickIntent, prompt: String) {
        let model = selectedModel
        messages.append(ChatLocalIntentTranscriptWriter.userMessage(text: prompt, model: model))

        func appendAssistant(text: String, widget: MessageWidget? = nil, streaming: Bool = false) -> String {
            ChatLocalIntentTranscriptWriter.appendAssistant(
                text: text,
                messages: &messages,
                widget: widget,
                streaming: streaming
            )
        }

        let priorUserText = messages.filter { $0.role == .user }.dropLast().last?.text
        if let result = ChatLocalIntentExecutor.execute(
            intent: intent,
            prompt: prompt,
            priorUserText: priorUserText,
            environment: localIntentExecutionEnvironment()
        ) {
            if let schedule = result.pendingNearAccountTrackerSchedule {
                pendingNearAccountTrackerSchedule = schedule
            }
            _ = appendAssistant(text: result.assistantText)
            if result.shouldHaptic {
                AppHaptics.selection()
            }
            return
        }

        let id = appendAssistant(text: "", streaming: true)
        currentAssistantMessageID = id
        isStreaming = true
        // Track the fetch in streamTask so cancelStream() can stop it, and
        // bail after the await if cancelled so we don't overwrite the turn
        // cancelStream() already finalized.
        streamTask = Task { [weak self] in
            guard let self else { return }
            let widget = await ChatLocalIntentWidgetService.widget(for: intent) {
                await self.briefDigestWidget()
            }
            guard !Task.isCancelled else { return }
            self.updateMessage(id) { message in
                message.isStreaming = false
                message.status = "completed"
                if let widget {
                    message.widget = widget
                } else {
                    message.text = ChatLocalIntentResponseFormatter.fetchFailed
                }
            }
            self.currentAssistantMessageID = nil
            self.isStreaming = false
            self.streamTask = nil
        }
    }

    /// Handles a compound local prompt if the dispatcher allows one. Data
    /// lookup compounds route through the model instead of this path.
    func handleCompoundIntent(_ intents: [QuickIntent], prompt: String) {
        let model = selectedModel
        messages.append(ChatLocalIntentTranscriptWriter.userMessage(text: prompt, model: model))
        let pendingID = ChatLocalIntentTranscriptWriter.appendAssistant(
            text: "Working on \(intents.count) lookups...",
            messages: &messages,
            streaming: true
        )
        currentAssistantMessageID = pendingID
        isStreaming = true

        // Best-effort Live Activity for the compound run. Side-effect only:
        // none of these calls affect the messages produced below.
        agentActivity.start(title: "Working on \(intents.count) lookups", total: intents.count)

        streamTask = Task { [weak self] in
            guard let self else { return }
            var produced = false
            var completed = 0
            for intent in intents {
                if Task.isCancelled { break }
                let widget = await ChatLocalIntentWidgetService.widget(for: intent) {
                    await self.briefDigestWidget()
                }
                guard !Task.isCancelled else { break }
                completed += 1
                self.agentActivity.update(stage: "Lookup \(completed) of \(intents.count)", completed: completed)
                guard let widget else { continue }
                produced = true
                let message = ChatLocalIntentTranscriptWriter.assistantMessage(
                    text: "",
                    widget: widget
                )
                self.messages.append(message)
            }
            guard !Task.isCancelled else {
                self.agentActivity.end()
                return
            }
            self.updateMessage(pendingID) { message in
                message.isStreaming = false
                message.status = "completed"
                message.text = produced ? "" : ChatLocalIntentResponseFormatter.compoundFetchFailed
            }
            if produced { self.messages.removeAll { $0.id == pendingID } }
            self.currentAssistantMessageID = nil
            self.isStreaming = false
            self.streamTask = nil
            self.agentActivity.end()
        }
    }

    func completePendingNearAccountTracker(account: String, schedule: BriefingSchedule, prompt: String) {
        pendingNearAccountTrackerSchedule = nil
        let model = selectedModel
        messages.append(ChatLocalIntentTranscriptWriter.userMessage(text: prompt, model: model))
        let result = ChatLocalIntentExecutor.completePendingNearAccountTracker(
            account: account,
            schedule: schedule,
            environment: localIntentExecutionEnvironment(),
            structured: true
        )
        messages.append(ChatLocalIntentTranscriptWriter.assistantMessage(
            text: result.assistantText
        ))
        if result.shouldHaptic {
            AppHaptics.selection()
        }
    }

    /// Passively records durable self-facts the user disclosed in an ordinary
    /// turn - no "remember" keyword needed. Silent by design (it never injects a
    /// chat reply) but logged to the activity log so the user can audit what was
    /// auto-learned, and stored as `.inferred` so recall labels it. Only genuinely
    /// new facts are logged; re-stating a known fact is a no-op.
    func captureInferredMemory(from text: String) {
        ChatLocalIntentExecutor.captureInferredMemory(
            from: text,
            memoryStore: memoryStore,
            activityLog: activityLog,
            isEnabled: passiveMemoryEnabled
        )
    }
}
