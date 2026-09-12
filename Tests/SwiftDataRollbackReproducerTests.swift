import Foundation
import SwiftData
import Testing

// Standalone SwiftData tests using only the test models below.
// The event test intentionally reproduces a process crash on affected runtimes.
@Suite(.serialized)
@MainActor
struct SwiftDataRollbackReproducerTests {
  @Test("Plain rollback restores retained schedule and variant relationships", arguments: [false, true])
  func retainedRelationshipsAfterRollback(loadOwnerBeforeRollback: Bool) throws {
    let container = try ModelContainer(
      for: RollbackProbeOwner.self, RollbackProbeSchedule.self,
      RollbackProbeVariant.self, RollbackProbeStep.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    )
    let context = container.mainContext
    context.autosaveEnabled = false
    let owner = RollbackProbeOwner()
    let schedule = RollbackProbeSchedule()
    let variant = RollbackProbeVariant()
    let step = RollbackProbeStep()
    // Register each initially unrelated model before connecting the graph.
    context.insert(owner)
    context.insert(schedule)
    context.insert(variant)
    context.insert(step)
    owner.schedule = schedule
    owner.variants = [variant]
    schedule.steps = [step]
    step.variant = variant
    try context.save()
    if loadOwnerBeforeRollback { try #require(owner.schedule === schedule) }
    try #require(schedule.owner === owner)
    try #require(step.variant === variant)
    try #require(step.schedule === schedule)

    // Replace mutable configuration, keeping the same owner and schedule.
    variant.retired = true
    let replacement = RollbackProbeVariant()
    context.insert(replacement)
    replacement.owner = owner
    let replacementStep = RollbackProbeStep()
    context.insert(replacementStep)
    replacementStep.variant = replacement
    replacementStep.schedule = schedule
    schedule.steps = [replacementStep]
    step.schedule = nil
    step.variant = nil
    context.delete(step)
    context.rollback()

    // Capture the first relationship read; an extra read can change lazy hydration.
    let retainedOwnerSchedule = owner.schedule

    // Check persisted state separately before traversing the remaining retained graph.
    let reader = ModelContext(container)
    let savedSchedule = try #require(reader.fetch(FetchDescriptor<RollbackProbeSchedule>()).first)
    let savedStep = try #require(reader.fetch(FetchDescriptor<RollbackProbeStep>()).first)
    #expect(savedSchedule.owner?.id == owner.id)
    #expect(savedStep.variant?.id == variant.id)
    #expect(savedStep.schedule?.id == schedule.id)
    #expect(try reader.fetchCount(FetchDescriptor<RollbackProbeVariant>()) == 1)
    #expect(try reader.fetch(FetchDescriptor<RollbackProbeVariant>()).allSatisfy { !$0.retired })

    print("SWIFTDATA-REPRO retained owner=\(schedule.owner === owner) variant=\(step.variant === variant) stepOwner=\(step.schedule === schedule) clean=\(!context.hasChanges)")
    print("SWIFTDATA-REPRO ownerScheduleID=\(String(describing: retainedOwnerSchedule?.id)) expected=\(schedule.id)")
    #expect(retainedOwnerSchedule?.id == schedule.id)
    #expect(retainedOwnerSchedule === schedule)
    #expect(schedule.owner === owner)
    #expect(step.schedule === schedule)
    #expect(step.variant === variant)
    #expect(schedule.steps?.count == 1)
    #expect(schedule.steps?.first === step)
    #expect(!variant.retired)
    #expect(!context.hasChanges)
  }

  @Test("A retained run accepts a new event after plain rollback")
  func attachEventAfterRollback() throws {
    let container = try ModelContainer(
      for: RollbackProbeRun.self, RollbackProbeEvent.self, RollbackProbeAction.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    )
    let context = container.mainContext
    context.autosaveEnabled = false
    let run = RollbackProbeRun()
    let original = RollbackProbeEvent()
    context.insert(run)
    context.insert(original)
    original.run = run
    try context.save()
    try #require(try context.fetchCount(FetchDescriptor<RollbackProbeEvent>()) == 1)

    // Add a lifecycle action and abandon the unsaved change. The run and its
    // previously saved event must remain usable through the retained references.
    let action = RollbackProbeAction()
    context.insert(action)
    action.run = run
    context.rollback()
    #expect(!context.hasChanges)
    let reader = ModelContext(container)
    #expect(try reader.fetchCount(FetchDescriptor<RollbackProbeAction>()) == 0)
    #expect(try reader.fetchCount(FetchDescriptor<RollbackProbeEvent>()) == 1)

    print("SWIFTDATA-REPRO attaching event to retained run")
    let next = RollbackProbeEvent()
    context.insert(next)
    next.run = run
    print("SWIFTDATA-REPRO attached event to retained run")
    try context.save()
    #expect(run.events?.count == 2)
    #expect(original.run === run)
    #expect(next.run === run)
    let finalReader = ModelContext(container)
    #expect(try finalReader.fetchCount(FetchDescriptor<RollbackProbeEvent>()) == 2)
    #expect(try finalReader.fetchCount(FetchDescriptor<RollbackProbeAction>()) == 0)
    #expect(try finalReader.fetch(FetchDescriptor<RollbackProbeEvent>()).allSatisfy { $0.run?.id == run.id })
  }
}

@Model
final class RollbackProbeOwner {
  var id: UUID = UUID()
  @Relationship(deleteRule: .cascade, inverse: \RollbackProbeSchedule.owner)
  var schedule: RollbackProbeSchedule? = nil
  @Relationship(deleteRule: .cascade, inverse: \RollbackProbeVariant.owner)
  var variants: [RollbackProbeVariant]? = nil
  init() {}
}

@Model
final class RollbackProbeSchedule {
  var id: UUID = UUID()
  var owner: RollbackProbeOwner? = nil
  @Relationship(deleteRule: .cascade, inverse: \RollbackProbeStep.schedule)
  var steps: [RollbackProbeStep]? = nil
  init() {}
}

@Model
final class RollbackProbeVariant {
  var id: UUID = UUID()
  var retired: Bool = false
  var owner: RollbackProbeOwner? = nil
  @Relationship(deleteRule: .nullify, inverse: \RollbackProbeStep.variant)
  var steps: [RollbackProbeStep]? = nil
  init() {}
}

@Model
final class RollbackProbeStep {
  var id: UUID = UUID()
  var schedule: RollbackProbeSchedule? = nil
  var variant: RollbackProbeVariant? = nil
  init() {}
}

@Model
final class RollbackProbeRun {
  var id: UUID = UUID()
  @Relationship(deleteRule: .cascade, inverse: \RollbackProbeEvent.run)
  var events: [RollbackProbeEvent]? = nil
  @Relationship(deleteRule: .cascade, inverse: \RollbackProbeAction.run)
  var actions: [RollbackProbeAction]? = nil
  init() {}
}

@Model
final class RollbackProbeEvent {
  var id: UUID = UUID()
  var run: RollbackProbeRun? = nil
  init() {}
}

@Model
final class RollbackProbeAction {
  var id: UUID = UUID()
  var run: RollbackProbeRun? = nil
  init() {}
}
