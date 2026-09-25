"""Builds the two GraphQL schemas from the .graphql files and connects each field to its resolver.

Using graphql-core directly (not a GraphQL framework) keeps the wire format
exactly what the Flutter app already speaks.
"""

from pathlib import Path

from graphql import build_schema

from telemetry import services as telemetry

from .. import hazards, places, reports, routing

HERE = Path(__file__).parent


def _submit(_root, _info, input):
    """submitAnonymousReport: rename the app's camelCase fields, then store the report."""
    names = {'clientId': 'client_id', 'speedMps': 'speed_mps', 'accuracyMeters': 'accuracy_meters',
             'observedAt': 'observed_at', 'recordedAt': 'recorded_at', 'isDemo': 'is_demo',
             'isMocked': 'is_mocked', 'photoToken': 'photo_token'}
    defect = reports.submit_anonymous_report({names.get(k, k): v for k, v in input.items()})
    return reports.acknowledgement(defect)


# --- /api/v1/graphql/anonymous/ ---------------------------------------------------
anonymous_schema = build_schema((HERE / 'anonymous.graphql').read_text(encoding='utf-8'))
_query = anonymous_schema.query_type.fields
_query['searchPlaces'].resolve = places.search_places
_query['publicHazards'].resolve = hazards.public_hazards
_query['drivingRoutes'].resolve = routing.driving_routes
anonymous_schema.mutation_type.fields['submitAnonymousReport'].resolve = _submit

# --- /api/v1/graphql/mobile/ ------------------------------------------------------
mobile_schema = build_schema((HERE / 'mobile.graphql').read_text(encoding='utf-8'))
mobile_schema.query_type.fields['collectionNoticeVersion'].resolve = telemetry.notice_version
_mutation = mobile_schema.mutation_type.fields
_mutation['grantCollectionConsent'].resolve = telemetry.grant
_mutation['revokeCollectionConsent'].resolve = telemetry.revoke
_mutation['revokeMyCollectionConsents'].resolve = telemetry.revoke_all
_mutation['uploadTelemetry'].resolve = telemetry.ingest
