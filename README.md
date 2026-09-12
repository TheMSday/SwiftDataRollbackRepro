# SwiftData rollback reproducers

A standalone iOS app and Swift Testing target demonstrating two native SwiftData
rollback problems. There are no external dependencies, production app models,
custom stores, CloudKit connections, rollback wrappers, or manual restoration.
Every test uses its own in-memory container with autosave disabled. Every new
model is explicitly inserted before connecting its relationships.

## Run in Xcode

1. Open `SwiftDataRollbackRepro.xcodeproj`.
2. Select the shared `SwiftDataRollbackRepro` scheme and an iOS destination.
3. Choose **Product > Test** (Command-U).

The app itself only displays test instructions; the reproductions are in
`Tests/SwiftDataRollbackReproducerTests.swift`. They run without environment flags.
Failing assertions and a test-host crash are the intended reproduction outcomes
on affected runtimes. Xcode may relaunch the test host after a crash.

Simulator testing requires no development team. For a physical iPhone, choose
your signing team for both targets in Signing & Capabilities and, if necessary,
change the example bundle identifiers. No developer team or credentials are
embedded in this project.

Minimum deployment target: iOS 17.0. Verified compiler: Xcode 27.0 (27A266a),
Swift 6 language mode, Debug configuration. Earlier Xcode versions were not tested.

## Tests

### 1. `retainedRelationshipsAfterRollback(loadOwnerBeforeRollback:)`

Four models: Owner → Schedule → Step, and Owner → Variant ← Step.

Save the original graph, then replace its step and variant configuration and
call plain `context.rollback()` (line 51). Compare the retained models against
original state read through a fresh context. The parameter controls whether the
owner's schedule relationship is read after the initial save and before mutation.

On iOS 27 RC, the unloaded case returns nil on the first `owner.schedule` read
(line 54), while `schedule.owner` and fresh-context relationships remain correct.
The preloaded case passes this minimal test.

### 2. `attachEventAfterRollback()`

Three models: Run, Event, Action. Both child collections have explicit inverses.

Save one run/event, attach an unsaved action, and call plain `context.rollback()`
(line 100). A fresh context correctly sees the original event and zero actions.
Insert another event and assign `next.run = run` (line 109).

On iOS 27 RC, that assignment aborts inside SwiftData while converting
`DefaultStoreSnapshotValueFuture` to `Array<RollbackProbeEvent>`.

## Observed results — 11 September 2026

All rows below use this standalone project and the same final source.

| Runtime | Relationship test | Event-after-rollback test |
| --- | --- | --- |
| iOS 17.5 (21F79), iPhone 15 Pro simulator | Unloaded case crashes inside `context.rollback()` with EXC_BAD_ACCESS/SIGSEGV and recursive SwiftData/Core Data frames; the loaded parameter case does not complete after this crash | Passes, including the final fresh-context checks |
| iOS 18.6 (22G86), iPhone 16 Pro Max simulator | Both parameter cases retain broken step links and retired state despite a clean context; stored state immediately after rollback is correct | No crash, but a subsequent event save reintroduces the discarded action; final zero-action assertion fails |
| iOS 26.5 (23F77), iPhone 17 Pro simulator | Same retained-step/retirement failures as 18.6 | Same final zero-action failure as 18.6 |
| iOS 27.0 RC (24A435), physical iPhone 15 Pro Max | Unloaded owner's schedule link becomes nil; preloaded case passes | Crashes at `next.run = run` with a snapshot-future-to-array cast failure |

The iOS 17 crash is a different failure signature from the iOS 27 event crash.
The tests deliberately include assertions about retained objects and fresh-context
readback; a clean `hasChanges` flag alone does not establish successful rollback.

The iOS 27 failures were reproduced multiple times. The final source was also
run once on each listed older simulator. SQLite stores, CloudKit synchronization,
Release optimization, and other OS builds have not been tested in this sample.

## Evidence and feedback drafts

`Evidence/` contains relevant console excerpts from each final run and crash-stack
excerpts for iOS 17.5 and iOS 27. Unrelated paths, device identifiers, and threads
are omitted. These are extracted evidence, not complete crash reports.

- [Relationship feedback draft](Feedback-Relationships.md)
- [Event crash feedback draft](Feedback-EventCrash.md)

Neither feedback report has been submitted. Keep the two issues separate when
filing, and attach this same project ZIP to each as needed.

## Command-line invocation

From this directory, replace the destination with an available simulator:

```sh
xcodebuild \
  -project SwiftDataRollbackRepro.xcodeproj \
  -scheme SwiftDataRollbackRepro \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/SwiftDataRollbackReproBuild \
  -resultBundlePath /tmp/SwiftDataRollbackReproResults.xcresult \
  -parallel-testing-enabled NO \
  test
```

Use a new result-bundle path for each run. Use `-only-testing` to select one case:

```text
-only-testing:SwiftDataRollbackReproTests/SwiftDataRollbackReproducerTests/retainedRelationshipsAfterRollback(loadOwnerBeforeRollback:)
-only-testing:SwiftDataRollbackReproTests/SwiftDataRollbackReproducerTests/attachEventAfterRollback()
```

For a physical device use `platform=iOS,id=DEVICE_UDID` and configure signing in
Xcode, or pass `DEVELOPMENT_TEAM=YOUR_TEAM_ID -allowProvisioningUpdates`.
