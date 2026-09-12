# SwiftData crashes linking an event to a retained run after rollback on iOS 27 RC

## Summary

A three-model SwiftData example crashes when setting an event's optional to-one
run relationship after rolling back a different child insertion on that run.
SwiftData aborts while converting `DefaultStoreSnapshotValueFuture` to the run's
optional event-array type.

## Environment

- Xcode 27.0 (27A266a), Swift 6, Debug.
- Physical iPhone 15 Pro Max, iOS 27.0 RC (24A435).
- Standalone Run/Event/Action models in an in-memory container, autosave disabled.
- Both child collections use cascade delete rules with explicit inverses.
- All models are inserted into the same context before relationship assignments.
- No app-specific code, custom stores, CloudKit, rollback wrappers or mementos.

## Steps to reproduce

1. Open the attached project and select the shared SwiftDataRollbackRepro scheme.
2. Select an iOS 27 RC destination.
3. Run `attachEventAfterRollback()`.
4. The test saves a Run and one related Event.
5. It inserts an Action and sets `action.run = run`, without saving.
6. It calls plain `context.rollback()` at line 100.
7. A fresh context correctly finds one Event and zero Actions.
8. It inserts a new Event into the original context, then sets `next.run = run`
   at line 109. This assignment crashes before the next save.

## Expected result

The retained run remains usable. Linking and saving the second event succeeds,
resulting in exactly two events and zero actions in a fresh context.

## Actual result

The process aborts during the relationship assignment:

```text
Could not cast value of type
'SwiftData.DefaultStore.DefaultStoreSnapshotValueFuture'
to 'Swift.Array<SwiftDataRollbackReproTests.RollbackProbeEvent>'.
```

The console prints `attaching event to retained run`, but never prints the next
`attached event to retained run` marker. The crash reproduces in multiple device
runs. Xcode may restart the host and reproduce the same abort.

## Comparison

- iOS 17.5 simulator: this final sample passes, including fresh-context readback.
- iOS 18.6 and 26.5 simulators: no cast crash, but saving the subsequent event
  reintroduces the rolled-back Action. The zero-action check immediately after
  rollback passes; the zero-action check after the next save fails.
- iOS 27 RC physical device: crashes at the relationship assignment.

## Attachments

- Standalone source project.
- `Evidence/ios27-console.txt` and `Evidence/ios27-crash-stack.txt`.
- Older-runtime console excerpts and the README result matrix.
