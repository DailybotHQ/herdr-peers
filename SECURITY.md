# Security policy

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x (latest: 0.1.0) | yes |

While herdr-peers is `0.x`, only the latest release receives fixes. Fixes
land on `main` first and ship in the next tag (see [CHANGELOG.md](CHANGELOG.md)).

## Reporting a vulnerability

**Do not open a public issue, discussion or pull request for a
vulnerability.** Report it privately:

- GitHub: **Security → Report a vulnerability** on this repository
  (private vulnerability reporting), or
- email **security@dailybot.com** with "herdr-peers" in the subject.

Include the herdr-peers version (`herdr-peers --version`), the Herdr version
(`herdr --version`), your OS, a minimal reproduction (the message text and
the command you ran), what happened, and what you expected. Do not include
real API keys or tokens — describe them by variable name.

## What to expect

| Step | Target |
| --- | --- |
| Acknowledgement | within 3 business days |
| Triage and severity assessment | within 7 days |
| Fix released — critical / high | within 30 days |
| Fix released — medium / low | in the next release |

We coordinate disclosure with you, publish a GitHub security advisory for
fixed issues, and credit reporters who want to be credited.

## Scope and threat model

What herdr-peers protects (the receiving agent's authority, the caller's
decisions, secrets, your panes and the delegation record), from whom, and
the residual risks it accepts — above all, that Herdr has no sender
authentication — are described in [docs/SECURITY.md](docs/SECURITY.md).
Vulnerabilities in Herdr itself belong to the Herdr project.
