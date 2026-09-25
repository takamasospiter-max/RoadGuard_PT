"""Helper for writing entries to the audit log (models.AuditLog)."""

from .models import AuditLog


def client_ip(request):
    """The caller's IP address, or None if it isn't known.

    REMOTE_ADDR is the address that connected to Django. Behind a reverse
    proxy it would be the proxy's address; handle X-Forwarded-For there.
    """
    return request.META.get('REMOTE_ADDR') if request is not None else None


def record(*, actor, actor_email, action, resource_type,
           resource_id=None, details=None, request=None):
    """Write one audit-log entry.

    actor         — the PortalUser who acted, or None (e.g. login with an unknown email)
    actor_email   — kept separately so the entry still says who it was if the
                    user is deleted later
    action        — short dotted verb, e.g. "user.invited", "defect.reviewed"
    resource_type — what kind of thing was affected, e.g. "portal_user"
    resource_id   — which one, e.g. "USR-004"
    details       — optional free text, e.g. "changed: role, status"
    request       — the current request, used to record the IP address

    Called only after the action has actually succeeded, so the log never
    records something that didn't happen.
    """
    AuditLog.objects.create(
        actor=actor,
        actor_email=actor_email,
        action=action,
        resource_type=resource_type,
        resource_id=resource_id,
        details=details,
        ip_address=client_ip(request),
    )
