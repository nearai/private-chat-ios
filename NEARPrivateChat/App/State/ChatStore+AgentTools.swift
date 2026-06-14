import Foundation

@MainActor
extension ChatStore {
    func executeIronclawMobileToolCalls(
        _ calls: [IronclawMobileToolCall],
        conversationID: String,
        promptAttachments: [ChatAttachment]
    ) async -> [IronclawMobileToolResult] {
        guard !calls.isEmpty else { return [] }

        var results: [IronclawMobileToolResult] = []
        for call in calls {
            switch call.name {
            case IronclawMobileToolNames.workspaceSnapshot:
                let snapshot = mobileWorkspaceSnapshot(
                    conversationID: conversationID,
                    promptAttachments: promptAttachments
                )
                results.append(IronclawMobileToolResult(
                    callName: call.name,
                    status: .completed,
                    summary: "Read the current iPhone Project/chat state.",
                    detail: snapshot.summary
                ))

            case IronclawMobileToolNames.runtimeCapabilities:
                results.append(IronclawMobileToolResult(
                    callName: call.name,
                    status: .completed,
                    summary: "Loaded the IronClaw Mobile capability manifest.",
                    detail: AgentStore.ironclawMobileCapabilityDetail
                ))

            case IronclawMobileToolNames.projectCreate:
                guard let name = call.arguments["name"], !name.isEmpty else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Missing project name.", detail: nil))
                    continue
                }
                let project = ensureMobileProject(named: name, includeConversationID: conversationID)
                results.append(.init(
                    callName: call.name,
                    status: .completed,
                    summary: "Created or selected project \"\(project.name)\".",
                    detail: nil
                ))

            case IronclawMobileToolNames.projectSelect:
                guard let name = call.arguments["name"], !name.isEmpty else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Missing project name.", detail: nil))
                    continue
                }
                guard let index = projectIndex(matching: name) else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Project \"\(name)\" was not found.", detail: nil))
                    continue
                }
                _ = projectStore.selectProject(projects[index])
                results.append(.init(
                    callName: call.name,
                    status: .completed,
                    summary: "Selected project \"\(projects[index].name)\".",
                    detail: nil
                ))

            case IronclawMobileToolNames.projectAddPromptFiles:
                results.append(addPromptFilesToSelectedProject(promptAttachments))

            case IronclawMobileToolNames.projectAddLink:
                results.append(addProjectLinkFromIronclaw(call))

            case IronclawMobileToolNames.projectSetInstructions:
                results.append(setProjectInstructionsFromIronclaw(call))

            case IronclawMobileToolNames.projectUpdateMemory:
                results.append(updateProjectMemoryFromIronclaw(call))

            case IronclawMobileToolNames.projectSaveNote:
                results.append(saveProjectNoteFromIronclaw(call))

            case IronclawMobileToolNames.conversationMoveToProject:
                guard let projectName = call.arguments["project_name"], !projectName.isEmpty else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Missing project name.", detail: nil))
                    continue
                }
                let allowCreate = call.arguments["create_if_missing"] == "true"
                let project: ChatProject
                if let index = projectIndex(matching: projectName) {
                    project = projects[index]
                } else if allowCreate {
                    project = ensureMobileProject(named: projectName, includeConversationID: nil)
                } else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Project \"\(projectName)\" was not found.", detail: nil))
                    continue
                }
                assign(conversationID: conversationID, to: project.id)
                _ = projectStore.selectProject(project)
                results.append(.init(
                    callName: call.name,
                    status: .completed,
                    summary: "Moved this chat into project \"\(project.name)\".",
                    detail: nil
                ))

            case IronclawMobileToolNames.conversationRename:
                guard let title = call.arguments["title"], !title.isEmpty else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Missing conversation title.", detail: nil))
                    continue
                }
                do {
                    try await conversationStore.renameConversation(id: conversationID, title: title)
                    await refreshConversations()
                    results.append(.init(
                        callName: call.name,
                        status: .completed,
                        summary: "Renamed this chat to \"\(title)\".",
                        detail: nil
                    ))
                } catch {
                    results.append(.init(
                        callName: call.name,
                        status: .failed,
                        summary: Self.displayFailureMessage(error.localizedDescription),
                        detail: nil
                    ))
                }

            case IronclawMobileToolNames.conversationPinSet:
                let pinned = call.arguments["pinned"] == "true"
                do {
                    try await conversationStore.setPinState(pinned, conversationID: conversationID)
                    await refreshConversations()
                    results.append(.init(
                        callName: call.name,
                        status: .completed,
                        summary: "\(pinned ? "Pinned" : "Unpinned") this chat.",
                        detail: nil
                    ))
                } catch {
                    results.append(.init(
                        callName: call.name,
                        status: .failed,
                        summary: Self.displayFailureMessage(error.localizedDescription),
                        detail: nil
                    ))
                }

            case IronclawMobileToolNames.conversationArchiveSet:
                let archived = call.arguments["archived"] == "true"
                do {
                    try await conversationStore.setArchiveState(archived, conversationID: conversationID)
                    await refreshConversations()
                    results.append(.init(
                        callName: call.name,
                        status: .completed,
                        summary: "\(archived ? "Archived" : "Unarchived") this chat.",
                        detail: nil
                    ))
                } catch {
                    results.append(.init(
                        callName: call.name,
                        status: .failed,
                        summary: Self.displayFailureMessage(error.localizedDescription),
                        detail: nil
                    ))
                }

            case IronclawMobileToolNames.webSearchSet:
                let enabled = call.arguments["enabled"] == "true"
                webSearchEnabled = enabled
                results.append(.init(
                    callName: call.name,
                    status: .completed,
                    summary: "Turned web search \(enabled ? "on" : "off").",
                    detail: nil
                ))

            case IronclawMobileToolNames.sourceModeSet:
                guard let rawMode = call.arguments["mode"],
                      let mode = ChatSourceMode(rawValue: rawMode) else {
                    results.append(.init(callName: call.name, status: .failed, summary: "Missing or invalid focus.", detail: nil))
                    continue
                }
                selectSourceMode(mode)
                results.append(.init(
                    callName: call.name,
                    status: .completed,
                    summary: "Set focus to \(sourceModeDetail).",
                    detail: nil
                ))

            case IronclawMobileToolNames.researchModeSet:
                let enabled = call.arguments["enabled"] == "true"
                researchModeEnabled = enabled
                results.append(.init(
                    callName: call.name,
                    status: .completed,
                    summary: "Turned research focus \(enabled ? "on" : "off").",
                    detail: nil
                ))

            default:
                results.append(.init(
                    callName: call.name,
                    status: .skipped,
                    summary: "This tool is not implemented in the iOS runtime yet.",
                    detail: nil
                ))
            }
        }
        return results
    }

    func mobileWorkspaceSnapshot(
        conversationID: String,
        promptAttachments: [ChatAttachment]
    ) -> IronclawMobileWorkspaceSnapshot {
        IronclawMobileWorkspaceSnapshot(
            selectedConversationID: conversationID,
            selectedConversationTitle: selectedConversationTitle,
            selectedProjectID: selectedProjectID,
            selectedProjectName: selectedProject?.name,
            projects: projects.map { project in
                IronclawMobileWorkspaceSnapshot.Project(
                    id: project.id,
                    name: project.name,
                    conversationCount: project.conversationIDs.count,
                    fileNames: project.attachments.map(\.name),
                    linkCount: project.links.count,
                    noteCount: project.notes.count,
                    hasInstructions: !project.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    hasMemory: !project.memorySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            },
            visibleConversationTitles: visibleConversations.map(\.title),
            archivedConversationCount: archivedConversations.count,
            webSearchEnabled: routingSemantics(for: .ironclawMobile).modelNativeWebToolEnabledByDefault ||
                routingSemantics(for: .ironclawMobile).appWebGroundingPolicy.isEnabledByDefault,
            promptFileNames: promptAttachments.map(\.name)
        )
    }

    func mobileProjectContext(promptAttachments: [ChatAttachment]) -> IronclawMobileProjectContext {
        ChatPromptContextBuilder.mobileProjectContext(
            selectedProject: selectedProject,
            selectedProjectAttachments: selectedProjectAttachments,
            promptAttachments: promptAttachments
        )
    }

    func promptOnlyAttachments(from attachments: [ChatAttachment]) -> [ChatAttachment] {
        let projectAttachmentIDs = Set(selectedProjectAttachments.map(\.id))
        return attachments.filter { !projectAttachmentIDs.contains($0.id) }
    }

    func activeAttachments(promptAttachments: [ChatAttachment]) -> [ChatAttachment] {
        let baseAttachments = sourceRoutingSemantics.attachesProjectFileSourcePack
            ? selectedProjectAttachments + promptAttachments
            : promptAttachments
        var seen = Set<String>()
        return baseAttachments.filter { attachment in
            if seen.contains(attachment.id) {
                return false
            }
            seen.insert(attachment.id)
            return true
        }
    }

    private func ensureMobileProject(named rawName: String, includeConversationID conversationID: String?) -> ChatProject {
        projectStore.ensureProject(named: rawName, includeConversationID: conversationID)
    }

    private func projectIndex(matching rawName: String) -> Int? {
        projectStore.projectIndex(matching: rawName)
    }

    private func addProjectLinkFromIronclaw(_ call: IronclawMobileToolCall) -> IronclawMobileToolResult {
        guard let rawURL = call.arguments["url"] else {
            return .init(callName: call.name, status: .failed, summary: "Missing or non-public HTTPS link URL.", detail: nil)
        }
        let title = call.arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ironclawResult(callName: call.name, projectResult: projectStore.addSourceLinkToSelectedProject(title: title, url: rawURL))
    }

    private func setProjectInstructionsFromIronclaw(_ call: IronclawMobileToolCall) -> IronclawMobileToolResult {
        let instructions = call.arguments["instructions"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ironclawResult(callName: call.name, projectResult: projectStore.setSelectedProjectInstructionsForTool(instructions))
    }

    private func updateProjectMemoryFromIronclaw(_ call: IronclawMobileToolCall) -> IronclawMobileToolResult {
        let memory = call.arguments["memory"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let shouldAppend = call.arguments["append"] != "false"
        return ironclawResult(callName: call.name, projectResult: projectStore.updateSelectedProjectMemoryForTool(memory, append: shouldAppend))
    }

    private func saveProjectNoteFromIronclaw(_ call: IronclawMobileToolCall) -> IronclawMobileToolResult {
        let text = call.arguments["text"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = call.arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ironclawResult(callName: call.name, projectResult: projectStore.saveToolNoteToSelectedProject(title: title, text: text))
    }

    private func addPromptFilesToSelectedProject(_ promptAttachments: [ChatAttachment]) -> IronclawMobileToolResult {
        let result = projectStore.addPromptFilesToSelectedProject(promptAttachments, maxAttachments: Self.maxProjectAttachments)
        return ironclawResult(
            callName: IronclawMobileToolNames.projectAddPromptFiles,
            projectResult: ProjectToolMutationResult(status: result.status, summary: result.summary, detail: result.detail)
        )
    }

    private func ironclawResult(callName: String, projectResult: ProjectToolMutationResult) -> IronclawMobileToolResult {
        let status: IronclawMobileToolResult.Status
        switch projectResult.status {
        case .failed:
            status = .failed
        case .skipped:
            status = .skipped
        case .completed:
            status = .completed
        }
        return .init(
            callName: callName,
            status: status,
            summary: projectResult.summary,
            detail: projectResult.detail
        )
    }
}
