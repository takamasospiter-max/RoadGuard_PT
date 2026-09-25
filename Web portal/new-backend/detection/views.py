"""HTTP API for an external AI engine service, plus the portal's view of a spot's detections.

AI engine service (authenticated with `Authorization: Api-Key <ROADGUARD_AI_API_KEY>`):

    POST /api/v1/ai/batches/claim/                {"limit": 10}
         → {"batches": [ {batchId, tripId, readings: [...], context: [...]} ]}
    POST /api/v1/ai/batches/<batchId>/results/    {"modelVersion": "...", "detections": [...]}
         or, if the model failed:              {"modelVersion": "...", "error": "..."}
         → {"batchId", "saved": <number of detections stored>}
    GET  /api/v1/ai/status/                       → how many batches are pending / done / ...

Full field-by-field description: docs/AI_ENGINE_CONTRACT.md.

Portal (normal portal login):

    GET  /api/v1/defects/<id>/detections/         → the detections that make up a spot
    GET  /api/v1/ai-engine/                       → the AI engine at a glance (dashboard card)
"""

import hmac
from datetime import timedelta

from django.conf import settings
from django.core.exceptions import ValidationError as DjangoValidationError
from django.db.models import Count, Max
from django.shortcuts import get_object_or_404
from django.utils import timezone
from django.utils.module_loading import import_string
from rest_framework import exceptions, serializers, status
from rest_framework.authentication import BaseAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from roadguard.models import Defect, HazardType, Severity
from telemetry.models import TelemetryBatch

from . import pipeline
from .engine import DetectionResult
from .models import Detection


# ---------------------------------------------------------------------------
# Authentication for the AI engine service
# ---------------------------------------------------------------------------

class AIEngineClient:
    """Stands in for `request.user` when the AI service calls the API."""
    is_authenticated = True
    email = 'system:ai-engine'


class AIEngineKeyAuthentication(BaseAuthentication):
    """Checks `Authorization: Api-Key <key>` against settings.ROADGUARD_AI_API_KEY.

    With no key configured the API is switched off entirely.
    """

    def authenticate(self, request):
        expected = settings.ROADGUARD_AI_API_KEY
        if not expected:
            raise exceptions.AuthenticationFailed('The AI engine API is disabled (no ROADGUARD_AI_API_KEY).')
        header = request.META.get('HTTP_AUTHORIZATION', '')
        # compare_digest takes the same time whatever the input, so the key
        # can't be guessed character by character from response times.
        if not header.startswith('Api-Key ') or not hmac.compare_digest(header[8:], expected):
            raise exceptions.AuthenticationFailed('Invalid AI engine API key.')
        return (AIEngineClient(), None)

    def authenticate_header(self, request):
        return 'Api-Key'


class AIEngineView(APIView):
    authentication_classes = [AIEngineKeyAuthentication]
    permission_classes = [IsAuthenticated]


# ---------------------------------------------------------------------------
# Serializers: JSON shapes of the AI engine API
# ---------------------------------------------------------------------------

def reading_json(reading):
    return {'kind': reading.kind, 'recordedAt': reading.recorded_at.isoformat(),
            'x': reading.x, 'y': reading.y, 'z': reading.z,
            'latitude': reading.lat, 'longitude': reading.lng,
            'speedMps': reading.speed_mps, 'gpsAccuracyMeters': reading.gps_accuracy_m}


class ClaimSerializer(serializers.Serializer):
    limit = serializers.IntegerField(min_value=1, max_value=100, default=10)


class DetectionInSerializer(serializers.Serializer):
    """One detection posted by the AI service."""
    detectedAt = serializers.DateTimeField()
    latitude = serializers.FloatField(min_value=-90, max_value=90)
    longitude = serializers.FloatField(min_value=-180, max_value=180)
    confidence = serializers.FloatField(min_value=0, max_value=1)
    intensity = serializers.FloatField(min_value=0, max_value=1, required=False, allow_null=True)
    severity = serializers.ChoiceField(choices=Severity.values, required=False, allow_null=True)
    hazardType = serializers.ChoiceField(choices=HazardType.values, default=HazardType.POTHOLE)


class ResultsSerializer(serializers.Serializer):
    modelVersion = serializers.CharField(max_length=60)
    detections = DetectionInSerializer(many=True, required=False, default=list)
    error = serializers.CharField(max_length=500, required=False, allow_blank=False)


# ---------------------------------------------------------------------------
# Views
# ---------------------------------------------------------------------------

class ClaimBatchesView(AIEngineView):
    """Hand out the next pending sensor batches to analyse (marks them "processing")."""

    def post(self, request):
        body = ClaimSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        batches = []
        for batch in pipeline.claim(limit=body.validated_data['limit']):
            data = pipeline.batch_input(batch)
            batches.append({
                'batchId': str(batch.id),
                'tripId': str(batch.trip_id),
                'receivedAt': batch.received_at.isoformat(),
                'readings': [reading_json(r) for r in data.readings],
                'context': [reading_json(r) for r in data.context],
            })
        return Response({'batches': batches})


class BatchResultsView(AIEngineView):
    """Receive the AI service's detections (or error) for one claimed batch."""

    def post(self, request, batch_id):
        batch = get_object_or_404(TelemetryBatch.objects.select_related('consent'), pk=batch_id)
        if batch.ai_status != TelemetryBatch.AIStatus.PROCESSING:
            return Response({'detail': f'Batch is "{batch.ai_status}", not "processing"; claim it first.'},
                            status=status.HTTP_409_CONFLICT)
        body = ResultsSerializer(data=request.data)
        body.is_valid(raise_exception=True)
        data = body.validated_data

        if data.get('error'):
            pipeline.mark_failed(batch, data['error'])
            return Response({'batchId': str(batch.id), 'saved': 0, 'status': 'failed'})

        results = [DetectionResult(detected_at=d['detectedAt'], latitude=d['latitude'],
                                   longitude=d['longitude'], confidence=d['confidence'],
                                   intensity=d.get('intensity'), severity=d.get('severity'),
                                   hazard_type=d['hazardType'])
                   for d in data['detections']]
        try:
            saved = pipeline.save_results(batch, results, data['modelVersion'])
        except DjangoValidationError as exc:
            return Response({'detail': '; '.join(exc.messages)}, status=status.HTTP_400_BAD_REQUEST)
        return Response({'batchId': str(batch.id), 'saved': len(saved), 'status': 'done'})


class AIStatusView(AIEngineView):
    """How many batches are in each state — a quick health check for the AI service."""

    def get(self, request):
        counts = dict(TelemetryBatch.objects.values_list('ai_status').annotate(n=Count('id')))
        return Response({
            'batches': {s: counts.get(s, 0) for s in TelemetryBatch.AIStatus.values},
            'detections': Detection.objects.count(),
            'engine': settings.ROADGUARD_AI_ENGINE,
        })


class DefectDetectionsView(APIView):
    """GET /api/v1/defects/<id>/detections/ — the evidence behind a spot (any portal user).

    Lets officers see how many phones hit the spot, when, and how hard, to
    judge its severity before verifying it.
    """

    def get(self, request, pk):
        defect = get_object_or_404(Defect, pk=pk)
        detections = defect.detections.order_by('-detected_at')[:500]
        return Response({
            'defectId': defect.pk,
            'deviceCount': defect.device_count,
            'observationCount': defect.observation_count,
            'severityScore': defect.severity_score,
            'publishedAt': defect.published_at.isoformat() if defect.published_at else None,
            'detections': [{
                'id': str(d.id),
                'detectedAt': d.detected_at.isoformat(),
                'latitude': d.lat, 'longitude': d.lng,
                'confidence': d.confidence, 'intensity': d.intensity, 'severity': d.severity,
                'modelVersion': d.model_version, 'isSimulated': d.is_simulated,
                # A short prefix is enough to tell phones apart without exposing the key.
                'device': d.device_key[:8],
            } for d in detections],
        })


class AIEngineOverviewView(APIView):
    """GET /api/v1/ai-engine/ — the AI engine at a glance, for the portal dashboard (any portal user).

    Answers "is the model running, and is it finding anything?" without
    loading the model: the version comes from the engine class and from the
    detections already stored.
    """

    def get(self, request):
        engine_path = settings.ROADGUARD_AI_ENGINE
        try:
            engine_class = import_string(engine_path)
            configured_version = getattr(engine_class, 'model_version', 'unknown')
            # The placeholder engine (detection.engine.NullEngine) never detects anything.
            is_placeholder = engine_class.__name__ == 'NullEngine'
        except ImportError:
            configured_version, is_placeholder = 'not found', True

        counts = dict(TelemetryBatch.objects.values_list('ai_status').annotate(n=Count('id')))
        last = TelemetryBatch.objects.aggregate(processed=Max('ai_processed_at'))
        latest_detection = Detection.objects.filter(is_simulated=False).order_by('-detected_at').first()
        latest_failure = (TelemetryBatch.objects.filter(ai_status=TelemetryBatch.AIStatus.FAILED)
                          .order_by('-ai_processed_at').first())
        since = timezone.now() - timedelta(hours=24)

        return Response({
            'engine': engine_path.rsplit('.', 1)[-1],
            'modelVersion': configured_version,
            'isPlaceholder': is_placeholder,
            'inlineProcessing': settings.ROADGUARD_AI_PROCESS_INLINE,
            'batches': {s: counts.get(s, 0) for s in TelemetryBatch.AIStatus.values},
            'lastProcessedAt': last['processed'].isoformat() if last['processed'] else None,
            'detections': {
                'total': Detection.objects.filter(is_simulated=False).count(),
                'last24h': Detection.objects.filter(is_simulated=False, detected_at__gte=since).count(),
                'simulated': Detection.objects.filter(is_simulated=True).count(),
            },
            'lastDetection': {
                'detectedAt': latest_detection.detected_at.isoformat(),
                'modelVersion': latest_detection.model_version,
            } if latest_detection else None,
            'lastError': {
                'at': latest_failure.ai_processed_at.isoformat() if latest_failure.ai_processed_at else None,
                'message': latest_failure.ai_error,
            } if latest_failure else None,
        })
