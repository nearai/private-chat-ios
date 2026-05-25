# NEAR Private Chat iOS Terms and Conditions

Effective date: May 25, 2026
Version: 2026-05-25
Status: Product/legal draft for counsel review before public release.

These Terms and Conditions ("Terms") govern access to and use of the NEAR Private Chat iOS application, including private AI chat, NEAR AI Cloud model routes, app-side web grounding, projects, files, sharing, signed transcript export, LLM Council, IronClaw Mobile, and hosted IronClaw agent workflows (collectively, the "App"). The App is made available by the entity that distributes it to you ("Operator," "we," "us," or "our"). Replace this Operator definition, contact information, venue, and any jurisdiction-specific clauses before release.

By creating an account, signing in, connecting a NEAR AI Cloud key, connecting IronClaw, uploading content, or otherwise using the App, you agree to these Terms. If you use the App for an organization, you represent that you are authorized to bind that organization.

## 1. Relationship to NEAR AI, NEAR AI Cloud, and IronClaw terms

The App may connect to NEAR AI services and IronClaw software or hosting. Your use of those services is also subject to the current terms and policies that apply to them, including:

- NEAR AI Services Terms of Service: https://near.ai/terms-of-service
- NEAR AI Cloud Terms of Service: https://near.ai/near-ai-cloud-terms-of-service
- NEAR AI Acceptable Use Policy: https://near.ai/acceptable-use-policy
- NEAR AI Privacy Policy: https://near.ai/privacy-policy
- IronClaw open-source repository and applicable licenses: https://github.com/nearai/ironclaw

If these Terms conflict with an upstream NEAR AI, NEAR AI Cloud, IronClaw, App Store, or third-party provider term for that upstream service, the upstream term controls for that upstream service. These Terms control App-specific features, local device behavior, user interface commitments, and your relationship with the Operator.

## 2. Eligibility and account security

You must be at least 18 years old and able to form a binding contract. You may not use the App if you are barred by applicable law, sanctions, export controls, or the terms of any connected service. You are responsible for maintaining the security of your account, device, API keys, local tokens, connected repositories, connected workstations, IronClaw credentials, and recovery methods.

You must promptly notify the Operator and relevant upstream provider if you suspect unauthorized access to your account, device, key, token, workstation, repository, or agent endpoint.

## 3. What the App does

The App provides an iOS interface for private AI chat and related workflows. Depending on your settings and available services, the App may:

- send prompts, files, project instructions, memory, saved links, and other context to private NEAR AI model routes;
- send prompts and selected context to NEAR AI Cloud routes, including open-weight models and premium closed-source models;
- use LLM Council to ask multiple selected models to compare, critique, or synthesize answers;
- run app-side web grounding or source collection when you enable web features;
- upload files, extracted text, links, or import data for chat and project context;
- create, store, export, import, archive, delete, and share conversations and projects;
- create signed transcript exports and verification metadata;
- run IronClaw Mobile or hosted IronClaw workflows that may inspect repositories, call tools, conduct research, write files, run tests, or interact with external systems;
- ask for approvals before sensitive hosted IronClaw actions, depending on the configured endpoint and App settings.

Features may change, be unavailable, be experimental, or require separate credentials, credits, subscriptions, permissions, or compatible upstream accounts.

## 4. Mandatory user attestation

Before signing in or using the App, you must affirmatively attest that:

- you have read and agree to these Terms;
- you are at least 18 years old and legally permitted to use the App and connected services;
- you will comply with the NEAR AI Services Terms, NEAR AI Cloud Terms, NEAR AI Acceptable Use Policy, applicable IronClaw terms/licenses, and third-party provider terms;
- you understand that prompts, files, links, project context, web queries, and agent instructions may leave your device when you enable or use networked routes;
- you understand that NEAR AI Cloud premium or closed-source model routes may be anonymized or proxied to third-party model providers and may not have TEE attestation in the App;
- you understand that attestation, when available, is cryptographic evidence about where a request was served, not a guarantee that an answer is accurate, safe, lawful, complete, or suitable for your use;
- you will review AI outputs and agent actions before relying on them, publishing them, or using them in consequential contexts;
- you will not use the App for prohibited, unlawful, unsafe, infringing, or abusive purposes.

The App may store the accepted Terms version, acceptance time, and account scope locally so that future versions can require renewed acceptance.

## 5. Privacy routes, Cloud routes, and anonymized third-party inference

The App may present different model routes with different privacy and proof properties:

- Private or attested routes may provide proof or verification metadata when supported by the upstream service. Verification can fail or be unavailable because of network, service, model, or reporting limitations.
- NEAR AI Cloud routes may include open-weight models and premium closed-source models. Some premium or closed-source models may be anonymously proxied or forwarded to third-party providers through NEAR AI Cloud. In those cases, the App should label the route as anonymized rather than attested.
- Third-party model providers may have their own terms, restrictions, data practices, rate limits, and safety policies.

Do not assume that every model has internet access, tool access, identical privacy guarantees, identical proof guarantees, or current factual knowledge. You are responsible for choosing a route appropriate for your use case.

## 6. Web grounding, search, links, and source packs

If you enable web grounding, source search, saved-link retrieval, or source-pack features, prompt-derived queries, URLs, snippets, and metadata may be sent to search engines, news providers, content hosts, NEAR AI services, model providers, or hosted IronClaw infrastructure. Search results and web snippets are untrusted content and may be inaccurate, malicious, outdated, copyrighted, or prompt-injection material.

You must not use the App to access private networks, unauthorized systems, illegal content, or content you do not have permission to process. You are responsible for complying with website terms, robots rules where applicable, copyright laws, privacy laws, and data-protection obligations.

## 7. Files, imports, projects, memory, and local storage

The App may let you attach files, extract text from documents, import chats, save links, save project instructions, store local memory, and cache conversation state. By uploading, importing, or saving content, you represent that you have all rights and permissions necessary for the App and connected services to process that content.

Do not upload or process protected health information, financial account data, government identifiers, biometric data, precise location data, confidential third-party data, trade secrets, source code, credentials, or personal data unless you have the required rights, lawful basis, contracts, disclosures, security controls, and approvals.

Local storage, backups, exports, pasteboard actions, notifications, crash logs, screenshots, and device-level sync may expose private content depending on device settings. Keep your device secure and review system-level backup and sharing settings.

## 8. IronClaw Mobile and hosted IronClaw agents

IronClaw features may allow AI agents to take actions beyond text generation. Depending on configuration, an agent may:

- inspect or modify files;
- clone, read, or write repositories;
- run commands, tests, package managers, build tools, browsers, or network calls;
- call external APIs or connected tools;
- use credentials, tokens, secrets, or environment variables that you configure;
- operate on a hosted workstation, local computer, or cloud endpoint.

You are responsible for every agent instruction, approval, tool connection, credential, repository permission, and action taken through your account or endpoint. You must review approval requests carefully, especially actions that write files, delete data, change infrastructure, spend money, publish content, alter repositories, access secrets, or affect third parties.

Do not connect IronClaw to systems you do not own or have permission to operate. Do not use agents for unauthorized access, malware, credential theft, vulnerability exploitation without authorization, spam, evasion, fraud, scraping in violation of law or terms, or any prohibited activity. Agent features may be experimental and may fail, stall, make mistakes, or execute unintended actions.

## 9. Sharing, collaboration, and exports

The App may let you share conversations, grant read or write access, import chats, export archives, or create signed transcript files. You are responsible for confirming recipients, permissions, links, organizations, and exported content before sharing.

Signed transcript export is intended to help detect tampering and preserve provenance metadata. It does not prove that every answer is true, that a model had a particular capability, that all missing attestations are safe, or that a transcript is legally admissible. Exports may include device identifiers, key identifiers, timestamps, model labels, route metadata, file names, source links, and other metadata.

## 10. Billing, credits, and API keys

Some NEAR AI Cloud or connected-provider routes may require API keys, usage credits, paid plans, rate limits, or subscriptions. You are responsible for fees, credits, usage, taxes, and spending caused by your account, keys, agents, automations, and connected users. The App may display usage or billing information for convenience, but upstream provider records control.

Never share API keys, session tokens, SSH keys, signing keys, or agent endpoint tokens in chat unless you understand the consequences and have appropriate controls.

## 11. Acceptable use

You must comply with the NEAR AI Acceptable Use Policy and all applicable laws. Without limiting that policy, you may not use the App or connected services to:

- violate rights, privacy, intellectual property, contracts, export controls, sanctions, or law;
- create, facilitate, or conceal fraud, phishing, spam, impersonation, deception, harassment, discrimination, or unlawful surveillance;
- generate or distribute child sexual abuse material, unlawful sexual content, terrorist content, violent extremist content, or instructions for serious harm;
- create malware, ransomware, credential theft, unauthorized access, evasion, exfiltration, or system compromise;
- bypass rate limits, billing, safety controls, attestation controls, authorization checks, or usage restrictions;
- process regulated data without required legal basis, disclosures, contracts, approvals, and safeguards;
- make automated consequential decisions about employment, credit, housing, education, health, legal rights, public benefits, insurance, law enforcement, or similar high-impact domains without appropriate human oversight and legal compliance;
- misrepresent AI-generated output as human-generated where disclosure is required.

We may suspend or terminate access, remove content, revoke tokens, disable features, or report unlawful activity when required or appropriate.

## 12. Output responsibility and no professional advice

AI outputs can be wrong, incomplete, outdated, biased, unsafe, infringing, or unsuitable. You are solely responsible for reviewing, validating, and deciding whether to use outputs. The App does not provide legal, medical, financial, tax, investment, professional engineering, safety-critical, or other professional advice. Consult qualified professionals before relying on outputs in those contexts.

## 13. Intellectual property

As between you and the Operator, you retain rights you already hold in your inputs, files, prompts, projects, and outputs, subject to upstream terms and applicable law. You grant the Operator and connected service providers the rights necessary to provide, secure, debug, support, and improve the App and connected services as described in these Terms and applicable upstream terms.

You must not upload, generate, use, or distribute content that infringes or misappropriates intellectual property, privacy, publicity, contractual, or other rights.

## 14. Security, proof, and limitations of confidential computing

The App may use cryptographic attestation, confidential computing, TEEs, CVMs, signed exports, local data protection, and route labels. These features reduce certain risks but do not eliminate all risks. They do not guarantee factual accuracy, model safety, endpoint integrity beyond the verified claim, absence of bugs, absence of prompt injection, immunity from malware, uninterrupted service, or protection against all side channels, operating-system compromise, user error, malicious links, misconfigured agents, or third-party service behavior.

You are responsible for securing your device, passcode, biometric settings, operating system updates, browser sessions, email account, keychain, backups, connected workstation, and cloud accounts.

## 15. Feedback and diagnostics

If you submit feedback, screenshots, diagnostics, logs, examples, or bug reports, you grant the Operator permission to use them to improve, secure, support, and market the App, unless a separate written agreement says otherwise. Do not include secrets or private third-party data in feedback unless specifically requested through an approved secure support channel.

## 16. Suspension and termination

We may suspend or terminate access to the App or any feature if we reasonably believe you violated these Terms, violated upstream terms, created security or legal risk, failed to pay required fees, exceeded limits, used unsupported beta features unsafely, or if an upstream service suspends or terminates access.

You may stop using the App at any time. Deleting the App may not delete server-side data, shared links, exported files, third-party logs, or upstream account data. Use in-app and upstream deletion/export controls where available.

## 17. Disclaimers

The App is provided "as is" and "as available" to the fullest extent permitted by law. We disclaim all warranties, including implied warranties of merchantability, fitness for a particular purpose, title, non-infringement, accuracy, availability, security, and quiet enjoyment. Beta, preview, developer, agent, bridge, hosted workstation, and experimental features may fail or change without notice.

## 18. Limitation of liability

To the fullest extent permitted by law, the Operator and its affiliates, officers, employees, contractors, licensors, and service providers will not be liable for indirect, incidental, special, consequential, exemplary, punitive, or lost-profit damages, or for loss of data, credentials, goodwill, business, revenue, or use, arising from or related to the App. Aggregate liability will not exceed the greater of the amount you paid directly to the Operator for the App in the 12 months before the claim or USD 100, unless applicable law requires otherwise.

Some jurisdictions do not allow certain limitations, so some limitations may not apply.

## 19. Indemnity

To the fullest extent permitted by law, you will defend, indemnify, and hold harmless the Operator and its affiliates, officers, employees, contractors, licensors, and service providers from claims, damages, liabilities, losses, costs, and expenses arising from your content, use of the App, agent actions, connected systems, violation of these Terms, violation of upstream terms, violation of law, or infringement or misappropriation of rights.

## 20. Changes to these Terms

We may update these Terms from time to time. The App may require you to accept a new version before continuing to use the App. Continued use after an update becomes effective means you accept the updated Terms.

## 21. Governing law and disputes

[Insert governing law, venue, arbitration, class-action waiver, consumer rights, and regional addenda after counsel review.] If an upstream provider term has a separate dispute process for that upstream service, that upstream process applies to disputes with that provider.

## 22. Contact

Questions, notices, and support requests should be sent to: [insert support/legal email].
