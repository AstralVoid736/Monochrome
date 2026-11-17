# Security policy

This is experimental alpha software using undocumented macOS display APIs. No security audit or guaranteed response time is claimed. Only the current alpha is actively maintained.

## Reporting a vulnerability

Do not publish secrets, credentials or a working exploit against another person in a public issue. Use this repository's **Security → Advisories → Report a vulnerability** channel when available: https://github.com/AstralVoid736/Monochrome/security/advisories/new . If GitHub does not offer private reporting, open a minimal issue asking for a private contact without including sensitive details.

## Boundaries

- The app contains no network, telemetry, updater, custom privileged helper or automatic startup path.
- It changes a system accessibility display preference only after a user action. This affects the whole display, not just the app.
- It refuses to overwrite another active color filter.
- Downloaded binaries are ad-hoc signed, not Developer ID signed or notarized. Do not disable system-wide security protections to run this alpha.
- The absence of network code is not an OS sandbox or a guarantee of safety.
