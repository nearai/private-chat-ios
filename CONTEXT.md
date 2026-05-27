# NEAR Private Chat iOS Context

Native iOS client context for private AI chat, mobile project context, source routing, sharing, attestation, and phone-safe agent work.

## Language

**NEAR Private Chat**:
Phone-first AI chat experience backed by the hosted private chat API.
_Avoid_: generic chat, mobile wrapper

**Conversation**:
A chat thread containing user prompts, assistant responses, branch variants, sharing state, and exportable transcript data.
_Avoid_: session, room

**Project**:
A local workspace bucket that groups conversations, instructions, memory, links, notes, and reusable files.
_Avoid_: folder, team, workspace

**Source Mode**:
User-selected context policy that decides whether the next response may use web, saved links, files, or combinations of those sources.
_Avoid_: search setting, context toggle

**Research Mode**:
Composer state that forces evidence-seeking behavior and report-style answers until the user chooses another source mode.
_Avoid_: web mode

**Model Route**:
The selected execution path for a response, such as NEAR Private, NEAR Cloud, IronClaw Mobile, Hosted IronClaw, or LLM Council.
_Avoid_: provider, model only

**LLM Council**:
Multi-model response mode where several selected models answer in parallel and a final synthesis compares results.
_Avoid_: ensemble, group chat

**IronClaw Mobile**:
Phone-safe agent runtime that can organize app-local chat, project, file, source, and settings state without desktop-only capabilities.
_Avoid_: IronClaw, desktop agent

**Hosted IronClaw**:
Authenticated public HTTPS bridge to a desktop-capable IronClaw environment.
_Avoid_: LAN gateway, localhost bridge

**Attestation**:
Privacy and execution evidence shown to the user for a selected model or response route.
_Avoid_: verification unless cryptographic proof is actually verified

**Shared Conversation**:
A conversation available through public link, direct invite, organization pattern, group share, or shared-with-me access.
_Avoid_: public chat

## Relationships

- A **Project** contains zero or more **Conversations**.
- A **Conversation** belongs to zero or one **Project**.
- A **Conversation** has exactly one active **Model Route** for a normal response.
- **LLM Council** uses multiple model routes and produces one synthesized response.
- **Source Mode** controls context for a response; **Research Mode** overrides it until changed.
- **IronClaw Mobile** is local to phone capabilities; **Hosted IronClaw** is remote desktop capability.
- **Attestation** describes evidence for a route or response; it is not automatically cryptographic verification.
- A **Shared Conversation** may be read-only or writable depending on granted permission.

## Example dialogue

> **Dev:** "If user adds files to a Project, do all Conversations get those files?"
> **Domain expert:** "Only Conversations in that Project use Project files, and Source Mode still decides whether those files are active for the next response."

## Flagged ambiguities

- "IronClaw" can mean **IronClaw Mobile** or **Hosted IronClaw**. Use exact term.
- "verification" can overclaim **Attestation**. Use "attestation" unless app verifies proof chain locally.
- "workspace" overlaps with **Project**. Use **Project** for app-local grouping.
