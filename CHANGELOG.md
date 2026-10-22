# Changelog

## Unreleased

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
