# SRS traceability — traveler client first

Baseline: RoadGuard_AI_SRS.pdf. Page numbers refer to PDF pages, not the shifted contents table. The repeated `XXMIS-TME-001` IDs are not repaired silently; UC numbers are used for references. See `VALIDATION.md` for executed Android checks. The implementation column below does not imply full SRS acceptance or verification of the remaining work.

| SRS item | Pages | Client delivery | Remaining work |
|---|---|---|---|
| Flutter, minimalist safe-driving UI | 10–11 | Material 3 mobile screens and low-distraction preview | Physical accessibility and driving-use study |
| UC-04 route planning | 14–15 | Origin/destination, fixture alternatives, local familiarity advisory and trip preview | Real map/routing service, geographic polylines, server trip history and actual guidance |
| UC-23 sensor collection | 16–17 | Eligibility rule, unconnected foreground raw sensor adapter and bounded outbox seam | Registered identity, revocable consent integration, native background lifecycle, GPS/motion alignment, DSP routing, measured >=10 Hz |
| UC-07 manual report | 18–19 | Pothole/crack, required single photo, optional notes, real GPS gate, local persistence | GraphQL/media upload and actual server New acknowledgement |
| UC-17 moderation | 19–20 | Read-only server status model; fixtures labeled sample | React administrator portal, MFA, invariant audit ledger and downstream publication |
| Edge-first SQLite | 13, 23–24 | Native SQLite repositories and transactionally capped 500-row outbox | Final record definition, orchestration, retry/backoff, automatic connectivity-driven sync and physical crash recovery tests |
| Stationary enforcement | 22 | Raw speed >0 locks fields and capture; save-time recheck | Validate GPS behavior across phones; approve extra quality gates |
| Algorithmic corroboration | 22, 26 | No client auto-confirmation | Server independent-device corroboration and epsilon/MinPts reconciliation |
| Hands-free warnings | 9, 20 | User-triggered example TTS and mute preference | Live push/stream, route relevance, deduplication and <=5 s server-to-device measurement |
| Battery <=5% extra/hour | 21 | No claim of compliance | Physical-device controlled power measurements with full sensing enabled |
| 100,000 trips; <500 ms lookup | 21 | Not a mobile-client claim | Backend capacity and geospatial tests |
| TLS 1.2+ | 24 | HTTPS-only transport seam; no cleartext production manifest | Native/gateway protocol verification, certificate/security review |
| Anonymous report stripping | 25 | Identity-free guest DTO and pixel-based image metadata reconstruction | Gateway allowlist/metadata verification and visible-content review |
| Validated erasure within 24 h | 25 | Clearly scoped local deletion only | Authenticated erasure endpoint, background processing, backups/audit relationships |
| SRS appendix open questions | 26 | Recorded as unresolved | DBSCAN tuning, phone-placement calibration, retention, bandwidth policy |

Onboarding and Riverpod are explicitly requested by the user in this conversation, not attributed to the SRS. Live account, map and backend behaviors are not silently replaced by the local demo: they remain outstanding requirements.
