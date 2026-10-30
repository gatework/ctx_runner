# Changelog

## Unreleased

## 0.5.0 (2026-10-30)

- Adopt immutable `Target` identity values and typed observation sources; share `records(name)` and configuration session behavior. Schema 4 uses `target`, validates aggregate status and full identity, and rejects empty applicability proof. Reject duplicate/unrequested batch work and mismatched returned snapshots. Align fingerprint depth with Document.

## 0.4.0 (2026-10-29)

- Add composed Snapshot and public Target contracts, independent collection status, and typed UTC times. Empty requests remain not_requested.
- Share observation scopes and acquisition times, requiring evidence for not_applicable. Preserve unfinished callback failures when cleanup also fails.
- Version collection, batch, change plan, review and execution documents with schema 3 and explicit kinds; reject older reports and plans.

## 0.3.0 (2026-10-29)

- Remove `Collection.new(strict:)`: provider contract failures consistently return structured diagnostics without replay and preserve the first failure. Batch consumers now expose `snapshot.observations`.

## 0.2.2 (2026-10-25)

- Share a single session delivery scope between collection and controlled execution; reject swallowed delivery violations, unfinished operations and cross-thread callbacks without replaying device actions.
- Preserve the first collection delivery failure when connection cleanup also fails; document module ownership and business operation boundaries.

## 0.2.1 (2026-10-24)

- Leave ctx_parser and ctx_driver dependencies unconstrained in the gemspec; retain the current collection, immutable report and execution contracts.

## 0.2.0 (2026-10-23)

- Breaking: report presenters, completion callbacks and progress callbacks now receive immutable string-keyed documents; remove Report#serializable and migrate consumers.
- Validate summary and execution documents before publication, remove stale completion after conversion failures, and confirm recovery checkpoint durability.
- Preserve collected evidence and the original exit when final progress abandons a batch without replaying progress.
- Use English evidence validation and report publication diagnostics.

## 0.1.1 (2026-10-23)

- Add shared offline evidence validation with mandatory target identity.
- Normalize owned JSON documents without freezing caller keys; support consumers without encode/decode roundtrips.

## 0.1.0 (2026-10-22)

- Centralize batch completion, cancellation priority and presentation failures; close result registration before finalization and preserve immutable summaries.

- Preserve successful sibling views when another query projection fails.

- Centralize collection lifecycle, shared query execution and immutable observation contracts.
- Share batch accounting and durable evidence publication across domain consumers.
- Execute confirmed typed changes with immutable journal checkpoints, readback verification and no replay.
- Preserve JSON configuration fingerprints while rejecting normalized key collisions.
- Add offline examples, fault-contract tests, Ruby 4.0.6 engineering gates and isolated package verification.
