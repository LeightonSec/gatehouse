# Security Policy

## Reporting a vulnerability

Please report security issues **privately** through GitHub: open the **Security** tab of this repository and choose **Report a vulnerability**. Please don't open a public issue for a security problem.

Useful details to include:
- what you found and where (file, resource or policy)
- how to reproduce it
- what an attacker could do with it

Reports are acknowledged as soon as practical. This is a one-person project, so there is no formal response time.

## Scope

Gatehouse is a **lab and portfolio project**, not a production service.
- Only the `main` branch is supported.
- The deployed environment exists only while it is being built or demonstrated, and all traffic is synthetic. There is no live production system and no real user data.
- In scope: the Terraform, gateway policies, CI/CD configuration, screening code and the design documents (`DECISIONS.md`, `THREAT_MODEL.md`).
- Out of scope: Microsoft Azure and GitHub services themselves. Please report issues in those platforms to Microsoft or GitHub directly.

## A note on the design

Known limitations and accepted risks are documented openly in `THREAT_MODEL.md`. If you find a threat the model doesn't cover, or a mitigation that doesn't hold, that is exactly the kind of report that's welcome.
