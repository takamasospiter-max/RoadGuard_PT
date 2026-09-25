# GraphQL integration handoff

The SRS supplies no executable wire schema. The workspace now implements and
connects explicit anonymous report/hazard/routing schemas and a separate
authenticated consent/telemetry schema, documented in
[backend LIVE_SERVICES.md](../../backend/docs/LIVE_SERVICES.md).
Traveler authentication uses the documented REST API. `RoadApi` and
`AuthService.mobileGraphql` are the connected transports; the original generic
The app talks to the backend through `RoadApi` (anonymous) and `AuthService` (signed in); both build their addresses in `lib/core/config/api_config.dart`.

The implementation is a local vertical slice, not final approval of all SRS
policy/production decisions. The original contract questions below remain a
handoff checklist where the implemented document does not resolve them.

## Contracts that must be agreed

**Route planning:** origin/destination coordinates and labels; request ID; candidate ID, real polyline/projection, distance, duration, route-relevant hazards, authoritative timestamps and history-based familiarity. Define stale/cached route behavior and anonymous history semantics.

**Report submission:** client-generated idempotency ID, category Pothole/Crack, optional notes, hazard coordinates, capture timestamp, position accuracy, stationary evidence and one sanitized image reference. Choose an explicit media-upload protocol; do not assume JSON GraphQL can upload arbitrary binary data. A validated response must include a server report ID and server status New. A local database write is not that response.

**Anonymous policy:** no bearer token, user ID, stable device token or EXIF/IPTC/XMP tags in anonymous manual report processing. Define protection against cookies/device metadata in the final network stack, gateway validation, rate limits and visible image identity. Independent-device corroboration and anonymous manual submissions require a documented relationship. Reject `isDemo` submissions as real evidence.

**Telemetry ingestion:** authenticated registration, independently verified consent, proposed batch schema, native observation times, aligned GPS evidence, units and device-rate diagnostics. Agree record limits with the SRS’s 500-record meaning. The server must honor idempotency IDs. Remove an outbox row only after explicit acknowledgement.

**Hazard delivery:** query/subscription or push schema, authoritative status/timestamp, route-relevance logic, removal/resolution events, stale/offline UI and duplicate alert IDs. Define the <=5 s clock from server scoring threshold clearance, not first road impact.

**Erasure:** authenticated user validation, accepted request timestamp, operation ID, status polling and the 24 h SRS deadline. Specify backups and immutable moderation audit interaction. Do not connect the existing local-delete button to a silent destructive remote request.

## Integration order

First connect registered/anonymous identity semantics and the report-upload vertical slice. Then real route/map reads, active trip persistence and server hazard updates. Enable sensing only after consent/revocation, native foreground/background behavior and outbox recovery are validated. Add backend DSP/DBSCAN and latency/resource testing without embedding a pretend classifier in Flutter.

Do not store passwords or bearer tokens in SharedPreferences or the SQLite report table. Select and review an OS-backed secure credential store when the authentication protocol is known. Keep live repositories separate from DemoRouteRepository; failed live requests must never fall back silently to fabricated road conditions.
