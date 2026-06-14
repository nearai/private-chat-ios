# Home Streams + Hostile Workflow Pass

Date: 2026-06-12

## Scope

Continued the product/design parity goal for the supplied streams-style Home, briefing, watcher, and generative-action surfaces.

This pass focused on two things:

- Home scope correctness: watchers must not count as briefings or render inside the Briefings tab.
- Hard workflow parsing: arbitrary current-event, release, regulatory, token/governance, supplement/calendar, and generated action-card prompts must become actionable drafts without falling back to canned ETH/Rolex/demo assumptions.

## Product Fixes

- `HomeFeedPlanner.visibleBriefings(..., scope: .briefings)` now excludes watcher-like briefings.
- Home scope counts now distinguish:
  - all feed items
  - non-watcher briefings
  - watcher-like items
  - chats
- Home briefing cards now use a generic `Ask follow-up` chip instead of model-generated long follow-up text on compact cards.
- Quick intent parsing no longer converts any known coin mention into a price tracker. Known coin widgets now require a price/value/quote cue, so `Track NEAR token unlock schedule and governance votes` becomes a custom web-grounded tracker instead of a NEAR price card.
- Quick intent display titles now clean `an ...` articles correctly and trim after truncation, fixing titles like `N AI news digest`.
- Digest display titles drop `covering ...` clauses so long workflow detail stays in the prompt, not the Home card title.
- Home recent-chat cards strip route/instruction scaffolding from display-only titles/previews. Existing stored titles are not renamed, but stale cards like `Rolex GMT-Master II . Use web search, lead with...` now render as `Rolex GMT-Master II`.
- Answer-thread compact trust chip now preserves the full `Get proof` label. It no longer truncates the proof action to the ambiguous `Get`.
- Watcher/briefing detail action controls now use a labeled `More briefing actions` button with a confirmation dialog instead of SwiftUI's `Menu`, removing the blank tappable target that appeared beside the header ellipsis in runtime snapshots.
- Home current-events/release-watch cards now disclose missing visible source evidence with a compact `No sources` chip when the preview/title looks recency-dependent but no source cue is present. This keeps old or unsourced current-news cards from looking as complete as sourced answers.
- Home cached-answer previews now strip Markdown display artifacts before compacting, including collapsed one-line headings like `## 1. ...`, bold markers, and bullet remnants. Old current-news cards now render as plain stream-card prose instead of raw Markdown.
- Answer-thread inline actions now use a labeled `More answer actions` button with a confirmation dialog instead of SwiftUI's `Menu`, removing the blank tappable target that appeared beside `Copy` / `Open` in runtime snapshots.
- Home source-gap cards now use the same amber recovery-card treatment as failed private-route cards: `Needs sources` in the header, amber rail/border, shortened preview height, and an `Open thread` footer action.
- Home display titles now collapse obvious current-news prompts like `What is news today? Include...` to `Today's news brief` for the feed card only. Stored conversation titles and prompts are not mutated.
- Threaded briefing/watch delivery rows now disclose source status. News widgets map their model-emitted source dots into the verified footer, and widget deliveries with no mapped sources show a compact `No source report` chip instead of looking silently verified.
- Empty Briefings/Watchers drafts are no longer canned demo subjects. `Draft briefing` now stages a generic editable briefing prompt for any topic/project/file/search; `Draft watcher` stages a generic editable watcher prompt for products, tokens, accounts, releases, regulations, or topics instead of hardcoding AI news or Rolex.
- Home `All` stream now suppresses chat cards whose canonical display title duplicates a visible live briefing/watcher. This keeps the stream from showing `Rolex GMT-Master II` twice in a row as both a watcher and an answer, while leaving the scoped `Chats` tab untouched.
- The stream de-dupe canonicalizer now uses the same display-title cleanup as the card UI, so instruction suffixes such as `. Use web search, lead with...` do not defeat the duplicate filter.
- News-widget follow-up affordances now separate the visible label from the staged draft. Ambiguous model text such as `Which of these stories should I track for updates?` renders as `Track one of these stories`, then stages a concrete watcher draft with the widget's story titles, cadence/source review language, and no auto-run.
- Home source-gap detection now checks the underlying message cache for real source evidence (`message.sources`, stored/extracted news-widget sources, action-plan source fields, and source-like text) before showing `Needs sources`. Compact previews can stay short without falsely marking sourced live widgets as unsourced.
- Home current-news previews now strip additional raw Markdown artifacts from live answers: horizontal rules (`---`), decorative emoji, paired/dangling bold markers, and stray asterisks. The stream card keeps the substance while matching the editorial reference instead of looking like copied Markdown.
- Home source-backed answer cards now carry a source summary chip in the footer instead of the generic `Private chat` chip. Stored web sources and news-widget sources collapse to labels such as `reuters.com` or `6 sources`, so Home discloses sourced/current-event work at a glance.
- Tracker creation no longer immediately runs the new briefing/watch workflow. The production `onCreateTracker` wiring now saves the tracker and exposes it in Watchers without burning a private-route inference call, so a fresh watcher does not instantly become a `Needs attention` card when OVH/private route is rate-limited.
- Briefing schedule labels now pin AM/PM casing (`Sat · 9:00AM`, `Tue · 6:00PM`) across tracker confirmations and Home feed cards.
- Scheduled watcher/briefing feed cards now hide internal prompt scaffolding. A never-run scheduled item renders as `Runs on schedule. Open to Run now or change cadence.` instead of dumping the generated `Using web search... Return a concise update...` prompt into Home.
- Source favicon handling now tries multiple privacy-scoped candidates for explicit web-search citations: Google S2 `domain_url`, legacy Google S2 `domain`, then `/favicon.ico`. The loader remains ephemeral/cookie-free and memory-cached.
- Web-search source detection now accepts real-world backend/source types such as missing type with a valid HTTPS URL, `search_result`, `organic`, `citation`, and `url_citation`, so Reuters/AP/Google-style citations do not silently skip favicon loading.
- Source fallback badges now use recognizable publisher marks/tints for common sources (Reuters, AP, Bloomberg, Google, BBC, WSJ, NYT, Guardian, CNBC) and better two-letter host initials for unknown sources.
- Home stream cards received a stronger editorial treatment: accent rails, tinted icon tiles, more intentional borders/status treatments, and favicon/initial source chips on briefing/news cards.

## Hostile Cases Added

Added coverage for:

- `Create a daily digest at 8am for SpaceX IPO, Iran war peace-talks status, and AI model releases with links.`
- `Track NEAR token unlock schedule and governance votes every Monday at noon.`
- `Watch for FDA GLP-1 safety label changes every weekday at 7am.`
- Live simulator send: `What is news today? Check current sources for SpaceX IPO/debut status, Iran war peace-talks status, and major AI product releases. Give concise bullets with links.`
- Live simulator tracker creation: `Track Sony A7 VI release date, preorder timing, and launch price every Saturday at 9am with current sources; alert me if the date changes.`

These are intentionally not product-specific canned demos.

## Validation

Focused tests passed:

- `testHomeFeedScopesKeepBriefingsAndWatchersSeparate`
- `testHardRecurringWorkflowPromptsBecomeActionableTrackers`
- `testSendDraftCreatesHardRecurringWorkflowWithoutPrivateRoute`
- `testEscalatingCurrentEventAndRegulatoryWorkflowsStayUserGrounded`
- `testEscalatingGenerativeTrackerMatrixCoversPricesReleasesAndDigest`
- `testWidgetActionPlanSeparatesConcreteCalendarRowsFromFuzzySupplementTrackers`
- `testHostileProductTrialPrivateChatIOSActionSurfaceContract`
- `testActionSurfacePlannerAugmentsHardMobileActionRequests`
- `testHomeConversationPreviewFormatterUsesCacheOrTitleFallback`
- `testHomeFeedPlannerHidesChatsThatDuplicateVisibleLiveItemsInAllStream`
- `testHomeConversationPreviewFormatterDetectsSourceCuePastCompactPreviewLimit`
- `testMessageRepositoryDetectsSourcesFromStoredNewsWidget`
- `testNewsWidgetTrackingChoiceStagesConcreteWatcherDraft`
- `testHomeConversationPreviewFormatterUsesCacheOrTitleFallback` now covers live-news Markdown artifacts (`---`, emoji, dangling `**`/`*`).
- `testMessageRepositorySummarizesMultiSourceNewsWidgets`
- `testEmptyHomeFeedDraftsStayGenericNotCannedDemoSubjects`
- `testUnknownAttestationUsesNoLocalProofReportCopy`
- `testHomeBriefingFeedPresentationShowsNewWatcherAsScheduledNotAttention`
- `testHomeBriefingFeedPresentationCarriesPrivateRouteFailureReason`
- `testHomeBriefingFeedPresentationMapsSignInFailureToRecoveryCopy`
- `testProductionTrackerPersistenceDoesNotAutoRunNewTracker`
- `testReleaseMonitorTrackerConfirmationMatchesHomeWatchersIA`
- `testSourceFaviconURLDerivationNormalizesPublicHosts`
- `testSourceFaviconURLDerivationRejectsEmptyPrivateAndNonHTTPInputs`
- `testSourceFaviconViewNetworkFetchIsOptIn`
- `testSourceFallbackMarksUseRecognizablePublisherInitials`
- `testWebSearchSourceProvenanceControlsNetworkFaviconsAndBadges`

Result bundles:

- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T19-28-41-855Z_pid37699_b349a812.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T19-37-09-696Z_pid37699_2ea2a991.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T19-38-16-199Z_pid37699_1d3adaaf.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T19-43-37-254Z_pid37699_736f5cca.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T19-50-23-108Z_pid37699_4a5e8b8d.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T20-19-50-235Z_pid37699_253109c5.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T20-31-44-704Z_pid37699_6ccc9747.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T20-34-08-220Z_pid37699_4f3bfa2f.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T20-40-31-874Z_pid37699_2fb5836d.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T20-46-08-393Z_pid37699_533b1412.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T21-11-27-762Z_pid37699_ea7b7e6f.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T21-19-50-026Z_pid37699_13d98ff7.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T21-22-46-971Z_pid37699_3e3f43d4.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T21-25-18-799Z_pid37699_fac5fe31.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T21-29-52-999Z_pid37699_269eb51d.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T21-31-37-355Z_pid37699_cba9b92d.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T21-36-13-310Z_pid37699_baed1f11.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T21-49-41-636Z_pid37699_a1a7baa5.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T21-50-44-768Z_pid37699_61bb4ac7.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T21-53-43-142Z_pid37699_dd38a535.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T21-56-42-985Z_pid37699_becbd6c2.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T22-00-49-721Z_pid37699_99d54952.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T22-02-21-710Z_pid16718_322bf154.xcresult`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T22-05-38-924Z_pid37699_8d811b4a.xcresult`

Build/install/launch passed after the parser fixes:

- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T19-39-12-869Z_pid37699_e5718b3d.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T19-45-00-621Z_pid37699_d759213e.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T19-51-16-321Z_pid37699_ed2197b0.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T20-10-54-050Z_pid37699_13c0df37.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T20-15-09-426Z_pid37699_5565cbe1.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T20-20-41-991Z_pid37699_1b7b4542.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T20-23-18-429Z_pid37699_e031c618.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T20-30-08-375Z_pid37699_8fc1f2f3.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T20-32-47-574Z_pid37699_f05fdc53.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T20-35-05-550Z_pid37699_903e9ce8.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T20-41-42-038Z_pid37699_7acd9f11.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T20-47-00-929Z_pid37699_6c5eed49.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T21-12-14-980Z_pid37699_74559108.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T21-20-53-508Z_pid37699_8afbd7a1.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T21-23-38-219Z_pid37699_2de5ac6e.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T21-26-16-280Z_pid37699_3b299271.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T21-30-51-464Z_pid37699_71bdf6ad.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T21-32-30-080Z_pid37699_52a530ea.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T21-37-20-760Z_pid37699_aab7aa02.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T21-51-29-456Z_pid37699_56134138.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T21-54-35-819Z_pid37699_ecff5924.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T21-58-46-271Z_pid37699_bb2f9bc8.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T22-01-49-671Z_pid37699_b746df59.log`
- `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T22-06-27-125Z_pid37699_3007b6ba.log`

Runtime snapshot evidence after the watcher-detail action-control fix:

- Closed watcher detail targets include `Back`, `More briefing actions`, and `Reply in thread…`; the previous blank `tap|button|||` target is no longer present.
- The action dialog exposes labeled actions (`Run now`, `Delete briefing`) instead of an unlabeled header action.
- Home runtime snapshot after the current-events trust-chip fix shows the stale current-news card as `Private chat, No sources, Current events`, while the private-route failure card remains an explicit `Needs attention` card.
- Home runtime snapshot after the preview cleanup shows the old current-news answer as plain text (`Today's News Briefing — June 12, 2026 1. SpaceX IPO... Confirmed: SpaceX went public...`) with no raw `##`, `**`, or `: -` artifacts.
- Answer-thread runtime snapshot after the inline-action fix exposes labeled targets for `Copy`, `Open`, `More answer actions`, `Open proof details`, and the composer chips; the previous blank `tap|button|||` target is no longer present.
- The answer action dialog exposes labeled actions (`Open output`, export formats, `Copy signed snippet`, `Regenerate`, and `Project`) instead of an unlabeled menu sibling.
- Home runtime snapshot after the source-gap recovery treatment shows the old current-news card as `Answer · 3h ago, Needs sources, Today's news brief, ... Open thread, Current events`; it no longer appears as a normal `Private chat` success card.
- Post-cleanup answer-thread screenshot confirms the card still opens correctly and the action row remains labeled (`Copy`, `Open`, `More`) while Home carries the source-gap disclosure before entry.
- Watcher-detail runtime snapshot now shows the Rolex metric delivery with `No source report`, while preserving the focused full-screen thread layout and labeled `More briefing actions`.
- Briefings empty-state runtime verification shows `Draft briefing` staging the generic briefing prompt in the composer, with `Web` inferred from the draft and no hardcoded AI-news/weather subject.
- Home runtime snapshot after the stream de-dupe shows `All` with the Rolex watcher once, followed by the current-events recovery cards. The adjacent duplicate `Rolex GMT-Master II` answer card no longer appears in `All`; it remains available under `Chats`.
- Live simulator hostile send succeeded through the current GLM 5.1 private route with `Web` inferred from the prompt. It rendered a compact `TODAY · 3 STORIES` widget covering SpaceX IPO/debut status, US-Iran peace-talk status, and AI product releases, with visible source initials, `Copy`/`Open`/`More` actions, and the inline follow-up affordance.
- External spot-check on June 12, 2026 matched the widget's broad story set: current search results included SpaceX IPO/debut reports, US-Iran peace-talk coverage, and Apple/Foundation Models AI release coverage. This validates routing/search behavior for this run, but does not remove the separate OVH/private-route capacity risk.
- Home runtime snapshot after the source-cache fix shows the successful live news card without the false `Needs sources` pill. It now renders as `Answer · 12m ago, Today's news brief, ..., Private chat, Current events`; the separate failed private-route card still correctly shows `Needs attention`.
- Thread runtime verification after the widget follow-up split shows the button label `Track one of these stories`. Tapping it stages `Create a watcher for one story from this brief...`, includes the three story options, asks the model to propose cadence/sources/monitoring before creating anything, enables Send, and flips the source chip to `Web` inferred from draft.
- Home runtime snapshot after preview cleanup shows the live news card as clean stream prose: `Today's Top Stories — June 12, 2026 SpaceX IPO — Record-Setting Debut Today SpaceX began trading on Nasdaq today (June 12)...`, with no raw `---`, emoji, `**`, or stray `*` marker.
- Home runtime snapshot after source-summary wiring shows the sourced live-news card footer as `6 sources, Current events` instead of `Private chat, Current events`. The private-route failure card remains separately labeled `Needs attention`.
- Runtime tracker creation before the production wiring fix reproduced the bad behavior: a newly-created Nintendo release watcher immediately auto-ran, hit the private-route limiter, and became a `Needs attention` card. After the fix, a fresh Sony release watcher created from Home stayed scheduled: `Watcher · Sat · 9:00AM`, `Runs on schedule. Open to Run now or change cadence.`, with no `Needs attention` status and no immediate private-route failure.
- Home runtime screenshot after the sidecar visual pass shows stronger editorial rails/icons/status styling instead of a blank flat feed. The old failed Nintendo/Apple cards remain as real historical failures, while fresh scheduled cards remain neutral.
- News-thread runtime screenshot after the source-icon pass shows visible source badges in the widget (`R`, `C`, `N`, `W`, `M`, `B`) rather than missing/invisible markers. Explicit `WebSearchSource` citations are now eligible for actual favicon fetches; model-emitted widget source domains remain local badge fallbacks by default for privacy.
- News-widget runtime screenshot after the structured-row pass shows each story as a row with compact source badges and source-count context instead of a flat bullet list.
- News-thread runtime screenshot after the widget-primary render policy shows the thread using the structured news widget as the answer surface: the duplicated prose/source carousel above the widget is gone when the widget already carries inline story sources, and the follow-up composer stages `Create a watcher for one story from this brief...`.
- Home `All` stream now applies an editorial recovery cap: healthy/scheduled/result cards lead, and repeated stale `Needs attention` / `Needs sources` cards are compressed to one recovery item in `All`. Scoped `Watchers` and `Chats` still expose the full operational lists.
- Runtime screenshot after the recovery-cap pass shows `All` leading with Rolex, scheduled Sony, and the sourced news brief, with only one Nintendo source-gap recovery card visible instead of multiple stale failure/recovery cards.
- Tracker/briefing detail now cleans old mid-word titles (`and la` from `launch price`) at presentation time, creates future tracker titles at word boundaries, replaces internal prompt scaffolding with concise user-facing About copy, and changes the primary action to `Run now` before the first delivery.
- Runtime screenshot after the briefing-detail pass shows the Sony watcher detail as `Sony A7 VI release date, preorder timing`, `Ready for first run`, concise About copy, schedule rows, and a `Run now` button.
- Delivered tracker threads now avoid false source warnings for web-grounded chart/metric widgets. News widgets still render real source tags; chart/metric trackers with no per-source tags but explicit web/current-source prompts show a neutral `Current-source run` footer instead of `No source report`.
- Runtime screenshot after the delivered-watcher pass shows the Rolex price thread with the chart widget and `Current-source run` footer.
- Scoped Watchers now prioritize healthy/delivered and scheduled items ahead of stale failures. `All` still keeps one recovery card high in the stream, but the Watchers tab now leads with the delivered Rolex watcher and scheduled Sony watcher before failed Nintendo/Apple items.
- A sidecar design pass tightened source badges for label-only publishers. `WidgetNewsSource` now centralizes `faviconIdentity`, readable source text, and fallback marks; `SourceFaviconResolver` recognizes labels such as `Reuters`, `Google News`, `Associated Press`, `Bloomberg`, `Axios`, and `TechCrunch`; Home mini source chips now use a 16pt mark tile with a subtle pill stroke.
- Source favicon loading remains provenance-gated by design: explicit web-search citations may fetch remote favicons through the ephemeral loader, while model-emitted widget sources stay local-only and render recognizable branded fallback marks instead of silently contacting favicon services.
- Healthy watcher cards now use a dedicated violet watcher accent. Amber is reserved for actual attention/failure/source-gap states, so delivered/scheduled watchers no longer look like warnings in the Stream surface.
- Runtime screenshot after the watcher-accent pass shows Rolex/Sony as active violet watcher cards, the sourced news card as blue, and the Nintendo source-gap card still amber.
- Runtime screenshot of the news answer thread confirms the structured widget remains usable after the source badge work: three source-backed rows, visible source marks, `Track one of these stories`, and a staged Web follow-up draft.
- Watcher detail runtime screenshot confirms the scheduled Sony watcher opens to a focused management detail with clean title/subtitle, `Ready for first run`, concise About copy, schedule rows, and `Run now`.
- Home composer route badge now visibly discloses the route, not only the model. Empty/private state renders as `Private · GLM 5.1`; current-source drafts render as `Private + Web · GLM 5.1`, matching the reference-style bottom controls and avoiding hidden route semantics.
- Focused XCTest passed for the news-widget render policy and source behavior:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T22-17-52-167Z_pid37699_e8a2f576.xcresult`
- Focused XCTest passed for Home briefing/chat recovery compression:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T22-25-38-320Z_pid37699_507951c6.xcresult`
- Focused XCTest passed for tracker-title/detail copy cleanup:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T22-31-14-855Z_pid37699_654396df.xcresult`
- Focused XCTest passed for threaded delivery source-status behavior:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T22-35-19-729Z_pid37699_fdb2b233.xcresult`
- Focused XCTest passed for Watchers scoped ordering:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T22-39-09-373Z_pid37699_6783acb2.xcresult`
- Combined source/widget badge XCTest passed after the sidecar source-label patch:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T22-49-35-763Z_pid37699_519756d1.xcresult`
- Focused Home watcher presentation/order XCTest passed after the watcher-accent pass:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T22-54-55-222Z_pid37699_bbe21617.xcresult`
- Focused Home composer route badge XCTest passed:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/result-bundles/test_sim_2026-06-12T22-59-04-341Z_pid37699_e2053926.xcresult`
- Simulator build/run passed after the render-policy patch:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T22-18-48-097Z_pid37699_a52af181.log`
- Simulator build/run passed after the Home recovery compression patch:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T22-26-33-594Z_pid37699_b6cda8ce.log`
- Simulator build/run passed after the briefing-detail cleanup:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T22-32-10-305Z_pid37699_41b5472b.log`
- Simulator build/run passed after the delivered-watcher source-status cleanup:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T22-36-15-571Z_pid37699_6f5d86a5.log`
- Simulator build/run passed after the Watchers scoped-order patch:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T22-40-03-589Z_pid37699_f553c24b.log`
- Simulator build/run passed after the source-label badge patch:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T22-45-32-835Z_pid37699_ccd141b9.log`
- Post-build screenshot capture was blocked by CoreSimulator teardown, not an app crash. The relevant logs reported `server died`, `Domain is tearing down`, and all simulator devices returned to `Shutdown` after launch. Re-run simulator visual QA once CoreSimulator is stable.
- Simulator build/run recovered and passed in a later run:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T22-52-13-380Z_pid37699_9cad5930.log`
- Simulator build/run passed after the watcher-accent pass:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T22-54-11-089Z_pid37699_8ca6cab8.log`
- Simulator build/run passed for the watcher-detail/composer badge verification pass:
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T22-56-59-100Z_pid37699_6a9f8462.log`
  - `/Users/abhishekvaidyanathan/Library/Developer/XcodeBuildMCP/workspaces/Playground-6c5f36151890/logs/build_run_sim_2026-06-12T23-00-06-661Z_pid37699_467850f8.log`

## Screenshots

- `review-artifacts/screenshots/2026-06-12-goal-continuation-2/home-all-streams-scope.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-2/home-briefings-empty-scope.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-2/home-watchers-rolex-scope.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-2/home-all-streams-post-parser-fix.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-2/home-all-streams-cleaned-recent-title.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-2/answer-thread-get-proof-label.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-3/home-streams-current.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-3/watcher-detail-rolex-clean-actions.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-3/home-streams-no-sources-chip.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-3/home-streams-clean-markdown-preview.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-3/answer-thread-actions-dialog.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-3/answer-thread-clean-actions.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-4/home-streams-source-gap-recovery.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-4/home-streams-concise-source-gap-title.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-4/answer-thread-after-home-source-gap.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-4/watcher-detail-rolex-focused-thread.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-4/watcher-detail-source-status.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-4/briefings-empty-generic-draft.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-5/home-stream-deduped-live-items.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-5/live-current-news-widget-success.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-6/home-sourced-live-news-no-false-warning.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-6/news-widget-actionable-tracker-draft.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-7/home-live-news-preview-clean-markdown.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-8/home-live-news-source-summary.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-9/home-watchers-scheduled-copy-build.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-9/home-watchers-scheduled-no-autorun.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-9/home-sidecar-stream-visual-polish.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-9/news-thread-source-icon-fallbacks.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-9/news-thread-structured-source-rows.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-9/news-thread-structured-source-rows-clean.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-9/home-stream-source-polish-live.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-9/news-thread-widget-primary-surface.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-10/home-all-stream-recovery-compressed.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-11/briefing-detail-clean-first-run.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-12/rolex-thread-before-source-status.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-12/rolex-thread-current-source-run.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-13/watchers-scope-healthy-first.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-14/home-stream-current-after-source-badges.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-14/news-thread-widget-source-badges.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-14/home-stream-watcher-accent.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-15/sony-watcher-detail-current.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-15/home-composer-private-route-visible.jpg`
- `review-artifacts/screenshots/2026-06-12-goal-continuation-15/home-composer-private-web-visible.jpg`

## External Caveat

Private-route reliability is still tracked separately in GitHub issue:

- https://github.com/abbyshekit/NEARPrivateChatIOS/issues/12

That issue covers the AASA/server problem and inference-time private route rate limiting. This pass removes client-side hardcoded parsing failures and verifies the Home/generative workflow surface, but it does not claim OVH/private inference capacity is fixed.
