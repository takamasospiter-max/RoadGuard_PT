"""Who is allowed to do what (SRS §2.3 access table).

- Any logged-in portal user can read everything and review defects.
- Only Admins can manage users and authorities, create or delete defects,
  and read the audit log.
"""

from rest_framework.permissions import SAFE_METHODS, BasePermission


class IsAdmin(BasePermission):
    """Allow the request only for a logged-in Admin."""

    message = 'Only Admins can do this'

    def has_permission(self, request, view):
        user = request.user
        return bool(user and user.is_authenticated and getattr(user, 'is_admin', False))


class IsAdminOrReadOnly(BasePermission):
    """Any logged-in user may read (GET); only Admins may change anything."""

    message = 'Only Admins can make changes here'

    def has_permission(self, request, view):
        user = request.user
        if not (user and user.is_authenticated):
            return False
        # SAFE_METHODS = GET, HEAD, OPTIONS — requests that don't change data.
        return request.method in SAFE_METHODS or getattr(user, 'is_admin', False)
