# Lift for Apple Watch

## Sync: why WatchConnectivity with the phone as the only database

- **The phone's SwiftData + CloudKit store stays the one database.** The watch never opens it. Two writers syncing one live workout through CloudKit would conflict, and CloudKit on watchOS delivers changes in minutes rather than seconds, which is too slow for a live set.
- **Phone → watch:** the whole open workout (`LiveWorkout`, a few KB of JSON) goes out as the WatchConnectivity *application context* (latest state, delivered when the watch app wakes) and as a *message* when the watch is reachable (instant). It's sent on every `ModelContext.didSave` (debounced) and on every rest change.
- **Watch → phone:** commands (`LiveCommand`: log set, undo, add exercise, set rest, rest start/+30 s/skip, finish, session started, Health saved). They go by message when the phone is reachable, otherwise by `transferUserInfo`, which is queued, delivered in order, and survives relaunches.
- **Nothing logged on the wrist is lost.** The watch applies each command to its copy at once and keeps it in `pending` (saved to disk) until a phone snapshot lists its id in `applied`. Each snapshot is rebased under the pending commands (`LiveReducer.rebase`). Commands are idempotent on the phone because sets carry their UUIDs and the phone keeps a list of applied ids.
- **Offline start:** a watch that starts before it hears from the phone uses its own workout id. An empty open log on the phone adopts that id; otherwise the watch's sets join today's log.

## Rest alerts: one buzz

`RestAlertPolicy`: while the watch runs its workout session and is reachable, the watch alerts with a haptic, wrist down too, because the session keeps it running. The phone schedules nothing in that case, since iOS would mirror its notification to the wrist as a second buzz. Otherwise the phone's local notification fires at the shared end time, so phone-only use works as before.

## Health: saved once

`HealthOwnership`: the watch saves workouts it ran an `HKWorkoutSession` for (Traditional Strength Training, with heart rate, external UUID = the workout id). The phone sees `device == "Watch"` and skips its own save, unless the watch reports that its save failed.

## Rep counting

See `RepCounter` in LiftCore. Each axis plus the gravity-vertical axis is band-passed and leak-integrated to a velocity. Out-and-back velocity lobes are counted with an adaptive Schmitt trigger. The counter is tested on synthetic 50 Hz fixtures only, with no real wrist recordings yet. The count is a starting estimate that the user corrects with the Crown before logging.

## Shared rules

- **Prefill:** one rule, `Target.prefill` (first set at the target, later sets = the set just logged). The phone runs it through `LiftStore.prefill`, including after a watch log; the watch's `Prefill.next` is a thin call to it.
- **Exercise search:** the Add exercise list uses the shared LiftCore search (spec.md §10) through `ExerciseFinder`, indexed once with `SearchEntry(library:)`.
