# SwiftData rollback returns nil for an unloaded saved relationship on iOS 27 RC

## Summary

After replacing related models and calling `ModelContext.rollback()`, the first
read of a retained owner's optional to-one schedule relationship returns nil.
The saved relationship is correct in a fresh context and the reverse relationship
still points to the original owner. Reading the owner's relationship after the
initial save but before the mutation prevents this specific nil result.

## Environment

- Xcode 27.0 (27A266a), Swift 6, Debug.
- Physical iPhone 15 Pro Max, iOS 27.0 RC (24A435).
- Standalone sample with four test models and an in-memory SwiftData container.
- Autosave disabled; all models explicitly inserted before relationships are set.
- No CloudKit, application services, rollback wrapper, or manual restoration.

## Steps to reproduce

1. Open the attached project and select the shared SwiftDataRollbackRepro scheme.
2. Select an iOS 27 RC destination.
3. Run `retainedRelationshipsAfterRollback(loadOwnerBeforeRollback:)`.
4. Observe the `false` parameter case: the owner's schedule relationship is not
   loaded after the initial save and before the attempted mutation.
5. The test replaces the original step/variant configuration, marks the old step
   deleted, and calls plain `context.rollback()` at line 51.
6. The first `owner.schedule` read at line 54 returns nil.

## Expected result

Rollback restores the original graph, and both relationship directions on the
retained owner/schedule agree with the saved graph. The step configuration and
variant retirement are also restored. No changes remain pending.

## Actual result

`retainedOwnerSchedule?.id == schedule.id` and retained-instance identity fail in
the unloaded case. `schedule.owner === owner`, step links, and the fresh-context
checks pass. The preloaded parameter case passes this small test.

Inspecting the relationship can change lazy-loading state. The test therefore
captures the first read before printing or additional retained-graph traversal.

## Comparison

On iOS 18.6 and 26.5 the owner relationship remains available, but retained step
relationships and variant retirement fail to roll back correctly in both cases.
On iOS 17.5 the unloaded case crashes inside `ModelContext.rollback()` instead;
its stack excerpt points to sample line 51. That older crash prevents completion
of the loaded parameter case in the combined run. See README for the exact matrix.

## Attachments

- Standalone source project.
- `Evidence/ios27-console.txt` for the nil relationship and passing preloaded case.
- `Evidence/ios175-crash-stack.txt` for the distinct older-runtime rollback crash.
- Console excerpts for the iOS 17.5, 18.6 and 26.5 comparisons.
