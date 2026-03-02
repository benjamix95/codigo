# Plan Flow Manual QA Checklist

Use this checklist to validate end-to-end behavior of plan mode, plan panel, TODO sync, build, walkthrough, and Mermaid rendering.

## Preconditions

- App launches with no runtime errors.
- At least one authenticated execution-capable provider is available.
- Start from a fresh conversation.

## 1) Keyboard shortcuts and panel toggle

- [ ] Press `Shift+Tab` in composer with text `fix parser`.
  - Expected:
    - Input becomes `/plan fix parser` immediately on first press.
    - Plan toggle is enabled.
- [ ] Press `Shift+Tab` in empty composer.
  - Expected:
    - Input becomes `/plan `.
    - Input remains focused.
- [ ] Press `Cmd+Shift+P` repeatedly.
  - Expected cycle:
    - Off/off -> inline plan on (no panel).
    - Inline on -> panel opens.
    - Panel open -> everything off.

## 2) Plan flow phases and panel behavior

- [ ] Send `/plan` request.
  - Expected:
    - Plan panel auto-opens.
    - Phase progress shown in analyzing/questioning/generating.
- [ ] Reach clarification phase.
  - Expected:
    - Clarification UI appears in panel.
    - Submit works for single-select, multi-select, and custom text.
- [ ] Reach proposal/options phase.
  - Expected:
    - Option chooser appears (or auto-select when only one option).
    - Plan details section visible when proposal is ready.

## 3) Custom responses

- [ ] In options view, submit custom response without `## Todo`.
  - Expected:
    - No immediate build.
    - A new `/plan ... Custom direction:` turn starts.
- [ ] Submit custom response with valid `## Todo` checklist.
  - Expected:
    - Build starts directly.

## 4) TODO visibility and scope

- [ ] During normal agent turn (no active plan), emit `todo_write`.
  - Expected:
    - Live TODO card appears in chat on latest assistant message.
- [ ] During plan build, emit canonical TODO updates.
  - Expected:
    - Plan panel Tasks section updates live.
    - Status sync reflected in plan steps.
- [ ] Switch to another conversation with different plan.
  - Expected:
    - Plan panel canonical TODOs are scoped to current conversation.
    - No cross-conversation TODO bleed.

## 5) MCP TODO tools and trace visibility

- [ ] Run `coderide_todo_write` from agent.
  - Expected:
    - Tool trace shows `todo_write` event.
    - TODO state updates in UI.
- [ ] Run `coderide_todo_read`.
  - Expected:
    - Tool trace shows `todo_read`.
    - Returned todos match current visible state.

## 6) Build execution and walkthrough

- [ ] Start build from selected plan option.
  - Expected:
    - Phase transitions to `building`.
    - Progress events/trace visible.
- [ ] On successful completion:
  - Expected:
    - Phase returns to ready/idle.
    - Walkthrough appears in plan panel.
    - Walkthrough references only current build turn (no old-turn contamination).
    - Steps section reflects canonical todos for this conversation only.
- [ ] Run rebuild from history entry.
  - Expected:
    - Rebuild starts correctly even if board had to be rehydrated.
    - Chosen path persists.

## 7) Mermaid rendering

- [ ] Plan content includes fenced Mermaid block with newline:
  - Example:
    - ```mermaid
      graph TD
      A --> B
      ```
  - Expected:
    - Diagram renders in panel.
- [ ] Plan content includes inline Mermaid fence:
  - Example:
    - ```mermaid graph TD; A-->B```
  - Expected:
    - Diagram still extracted/rendered.
- [ ] Insert two identical Mermaid blocks.
  - Expected:
    - Both render consistently (no identity glitch).
- [ ] Simulate CDN unavailable (offline / blocked).
  - Expected:
    - Inline error message shown in diagram card.
    - App remains stable.

## 8) Regression checks

- [ ] Closing/opening plan panel does not corrupt plan state unexpectedly.
- [ ] Latest assistant message still shows live TODO card when todos exist.
- [ ] Tool trace still includes operational events (search/edit/command/todo).
- [ ] No linter/test regressions.

---

## Final pass criteria

Mark QA as passed only if all core scenarios pass:

- Shortcuts (`Shift+Tab`, `Cmd+Shift+P`)
- Clarification + options + custom response
- Build + walkthrough
- TODO chat/panel/MCP visibility
- Mermaid render (normal + inline + failure mode)
