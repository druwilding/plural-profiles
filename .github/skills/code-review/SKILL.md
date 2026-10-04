---
name: code-review
description: How to review pull requests in Plural Profiles — what to check most carefully, what not to flag, and how to write findings. Use when reviewing a pull request or a diff in this repository.
---

# Reviewing Plural Profiles pull requests

Read `.github/copilot-instructions.md` first: it describes the stack, the conventions and how chat works. This file is about where review attention pays off here.

## Check most carefully

**Language.** Plural people are never called a "system", anywhere: copy, code, comments, test names. Flag it every time. British English in copy and comments.

**Accessibility.** It's a core value of the app, so treat gaps as real findings, not nitpicks:
- Is anything shown only visually (a dot, a colour, an icon) without text for screen readers?
- Is anything reachable only by hovering (a `title` tooltip, a hover reveal) with no keyboard or touch route?
- Does it work in forced-colors (high-contrast) mode? Themed colours there should become system colours, and text needs to stay visible.
- Does it hold up at large text sizes on a narrow screen? Fixed pixel widths and heights that hold text are suspect.

**Theme colours.** A colour in CSS should come from a root variable, and chat should use the `--chat-*` ones. The exception (colours drawn outside the page's CSS, like the favicon badge) is in the instructions.

**Turbo.**
- Does the change hold up when the page is restored from Turbo's cache (going back), or shown as a preview first? State added by JavaScript ends up in the cache.
- A GET must not change anything: Turbo prefetches links on hover.
- A form whose response redirects between the main domain and `chat.` must not be submitted by Turbo.

**Live updates in chat.**
- A broadcast is drawn once, in the sender's request: it can't depend on who's viewing (time zone, unread state, permissions) unless the browser fixes it up.
- Broadcasts missed while a connection is down are gone for good.
- Two deliveries of the same element (a broadcast and a response, say) can reorder or duplicate it.
- Races between a response and a broadcast, or a broadcast and the page's own update, are where chat bugs have come from.

**Losing what someone typed.** A reload, a replaced form or a cleared field must not throw away a draft or unsaved changes without reason.

**Tests.**
- A bug fix should come with a test that would have failed without it.
- System tests must wait for state rather than sleep and hope.
- A test that changes the shared browser (its window size, emulated media, stubs on `window`) must put it back.

## Don't flag

- Long comments explaining *why* code is the way it is. They're the house style.
- RuboCop-level style (rubocop runs in CI).
- Hard-coded colours in canvas-drawn images (the favicon badge), which can't use CSS variables.
- Chat pickers being alphabetical while other lists follow the person's custom order. That's deliberate.

## Writing findings

- Lead with the concrete failure: what someone does, what goes wrong, and for whom.
- Point at the line that causes it, and suggest a fix that fits the existing code.
- Say how sure you are when it depends on timing or on a browser's behaviour.
- One finding per problem.
