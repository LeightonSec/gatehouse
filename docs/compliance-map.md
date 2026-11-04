# Compliance Map

How Gatehouse's controls would support an organisation's obligations under EU and Swedish law (D15). **Gatehouse itself is not claimed to be in scope of any of these laws.** This is a design reference, not legal advice.

The map grows with the build: every phase gate adds the controls that phase delivers, each linked to the test that proves it in `THREAT_MODEL.md`. A control is only marked "evidenced" once its test has passed.

## Laws covered

| Law | Status (checked 2026-11-04) | Verified against | Relevance to Gatehouse |
| --- | --- | --- | --- |
| NIS2, implemented in Sweden by the Cybersecurity Act (cybersäkerhetslag, SFS 2025:1506) | In force since 15 January 2026. Chapter 2: notification of a significant incident within 24 hours of becoming aware (section 5), within 72 hours (section 6; 24 hours for trust service providers), final report within one month (section 8) | The statute (riksdagen.se) | Security measures (access control, logging, incident detection, supply chain) and the detection-to-notification clock |
| Cyber Resilience Act, Regulation (EU) 2024/2847 | In force since 10 December 2024. Reporting obligations (Article 14) from 11 September 2026. Fully applicable from 11 December 2027 | European Commission; recitals 15, 18 and 20 on EUR-Lex | Built CRA-ready. Likely outside scope as a non-monetised public repo; paid deployment or support for clients could change that (recital 15) |
| EU AI Act, as amended by the Digital Omnibus on AI, Regulation (EU) 2026/1744 | Amendment in force since 27 July 2026. High-risk obligations reported as moved to 2 December 2027 (Annex III) and 2 August 2028 (Annex I) | Entry into force: EUR-Lex. **High-risk dates: two secondary sources only, not yet verified against the regulation's text** | A governance control for AI deployers; not itself a high-risk system |
| GDPR | In force | Not re-checked | Prompt logging (D10) and personal data in captured attacker prompts (D13) |

## Platform rules (not law, but binding)

| Source | What it means for Gatehouse | Decision |
| --- | --- | --- |
| Microsoft Enterprise AI Services Code of Conduct (v4.0, 1 May 2026) | Testing safety systems for your own use is permitted. Generating High-Risk Content (malicious cyber activity, CBRN) needs prior approval through a Limited Access application. Sending harmful content to Content Safety through its intended use is not by itself a violation | D16, D9 |
| Microsoft Penetration Testing Rules of Engagement | No notice needed to test your own resources; breaking out of AI system boundaries explicitly encouraged; DoS testing and excessive traffic prohibited; Microsoft may interrupt even valid tests | D16, T3, T18 |
| Azure OpenAI abuse monitoring | Recurring jailbreak attempts raise an abuse score that can lead to suspension | T18 |

## Control map

| Control | Implemented in | Evidence (test) | NIS2 | CRA | AI Act | GDPR | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| *Added phase by phase* | | | | | | | |

## Sources

Primary:
- [Cybersäkerhetslag (2025:1506), riksdagen.se](https://data.riksdagen.se/dokument/sfs-2025-1506.text)
- [Cybersäkerhetsförordning (2025:1507), riksdagen.se](https://www.riksdagen.se/sv/dokument-och-lagar/dokument/svensk-forfattningssamling/cybersakerhetsforordning-20251507_sfs-2025-1507/)
- [Regulation (EU) 2024/2847 (CRA), EUR-Lex](https://eur-lex.europa.eu/legal-content/EN/TXT/HTML/?uri=OJ%3AL_202402847)
- [European Commission: CRA summary](https://digital-strategy.ec.europa.eu/en/policies/cra-summary)
- [Regulation (EU) 2026/1744 (Digital Omnibus on AI), EUR-Lex](https://eur-lex.europa.eu/eli/reg/2026/1744/oj?locale=en)
- [Microsoft Enterprise AI Services Code of Conduct](https://learn.microsoft.com/en-us/legal/ai-code-of-conduct)
- [Microsoft: Penetration testing](https://learn.microsoft.com/en-us/azure/security/fundamentals/pen-testing)
- [Microsoft: Planning red teaming for LLMs](https://learn.microsoft.com/azure/ai-foundry/openai/concepts/red-teaming)
- [Microsoft: Azure OpenAI abuse monitoring](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/concepts/abuse-monitoring)

Secondary (used only where the primary text could not be read):
- [Future of Privacy Forum: the AI Act timeline under the AI Omnibus](https://fpf.org/blog/the-ai-act-implementation-timeline-what-changes-under-the-ai-omnibus)
- [National Law Review: the Digital Omnibus on AI enters into force](https://natlawreview.com/article/eu-digital-omnibus-ai-enters-force)

## Known gaps in verification
- The CRA's Article 71 (application dates) and Article 3 definitions were not read directly; the dates come from the Commission's official summary.
- The AI Omnibus's operative articles were not read directly; the high-risk dates come from the two secondary sources above, which agree.
- GDPR was not re-checked for this version.
