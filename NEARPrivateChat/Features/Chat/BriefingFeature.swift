/**
 INTEGRATION

 The integrator must wire these points elsewhere:
 1. Own one `BriefingStore` and inject the real `runner` that sends `briefing.prompt` through the chat send path, then uses `MessageWidget.extract` on the answer.
 2. Insert `TodaySection(...)` at the top of `ConversationListView`'s main `LazyVStack` around line 252, gated to the default filter plus empty search.
 3. Register `BGTaskScheduler` and `UNUserNotificationCenter`, and call `store.runDue` on foreground.
 4. Add Info.plist keys: `UIBackgroundModes` with processing/fetch, and `BGTaskSchedulerPermittedIdentifiers`.
 */

import Foundation
import SwiftUI
@preconcurrency import UserNotifications


// Phase 12 split: briefing models, store, builder, and views live in focused files.
