---
alwaysApply: true
---

## Definition

- The app's name is Yamete.
- This is a native macOS SwiftUI app.

## Commit Discipline

- Commit after every discrete action. Each meaningful change such as adding a feature, fixing a bug, refactoring, updating docs, adjusting packaging, or improving release automation should be committed individually before moving on.
- Commit messages must use the intent as the title and a concise summary of what was done as the description/body.
- Do not batch unrelated changes into a single commit.
- If a task involves multiple steps, commit after each step, not all at the end.

## Branching

- If the current branch is `main`, commit directly on `main`.
- Prefer one branch and PR per logical unit of work when working off `main`.
- Only split work into multiple PRs when dependency order or review scope makes it necessary.

## Releases

- When asked to create a release, make sure `main` is pushed first, then create or update the GitHub release tag and let `.github/workflows/release.yml` build the signed and notarized DMG.
- Releases must be published immediately. Do not use draft releases unless explicitly requested.
- Include release notes with concise, descriptive bullet points explaining what changed for the user.
- Each bullet should describe the user-facing change, not implementation details.
- Do not ship a release if the notarization workflow fails.

## Comments

- By default, avoid writing comments.
- If you write one, it should explain why, not what.

## General

- Prefer simple SwiftUI code over extra abstraction.
- Avoid creating unnecessary types or wrappers when the code is only used once.
- Prefer small, readable views and direct state flow.
- Use AppKit only when SwiftUI does not cover the macOS behavior cleanly.
- Keep commits small and reviewable.
- Run `swift build` before committing.
- Run `./scripts/build-release-assets.sh <tag> <output-dir>` when changing packaging or release behavior.

## SwiftUI

- Prefer straightforward `ObservableObject` and view composition over elaborate architecture.
- Keep view state local when it is truly local.
- Extract subviews only when it improves readability or reuse.
- Match existing SwiftUI patterns in the repo before introducing new ones.
