"""Runs one GraphQL request safely and shapes the reply like the app expects.

Safety limits (the anonymous endpoint is open to anyone):
- one operation per request, no fragments, at most 5 top-level fields,
  80 fields in total and 8 levels of nesting;
- no schema introspection (`__schema`, `__type`) — the schema files are in
  the repository instead.

Reply shapes:
- invalid request            → HTTP 400 {"errors": [{"message"}]}
- valid request, rule broken → HTTP 200 {"data": ..., "errors": [{"message", "extensions": {"code"}}]}
  (the app reads the message, e.g. "Photo token has expired. Upload the photo again.")
"""

import logging

from django.core.exceptions import ValidationError
from graphql import GraphQLError, execute_sync, parse, validate
from graphql.language.ast import FieldNode, OperationDefinitionNode

log = logging.getLogger(__name__)

MAX_QUERY_CHARS = 12_000


class BadRequest(Exception):
    """The request itself is malformed → HTTP 400."""


def _check_document(query):
    """Parse the query text and enforce the size/shape limits above."""
    document = parse(query, max_tokens=1000)
    if len(document.definitions) != 1 or not isinstance(document.definitions[0], OperationDefinitionNode):
        raise BadRequest('Send one operation without fragments.')
    operation = document.definitions[0]
    if len(operation.selection_set.selections) > 5:
        raise BadRequest('Limit an operation to five root fields.')

    total = 0

    def walk(selection_set, depth):
        nonlocal total
        if depth > 8:
            raise BadRequest('Query nesting exceeds the supported limit.')
        for node in selection_set.selections:
            total += 1
            if total > 80 or not isinstance(node, FieldNode):
                raise BadRequest('Limit operations to 80 fields without fragments.')
            if node.name.value.startswith('__'):
                raise BadRequest('Schema introspection is disabled; use the checked-in schema files.')
            if node.selection_set:
                walk(node.selection_set, depth + 1)

    walk(operation.selection_set, 1)
    return document


def run(schema, body, request):
    """Execute `body` ({query, variables, operationName}) → (reply dict, HTTP status)."""
    try:
        if not isinstance(body, dict) or set(body) - {'query', 'variables', 'operationName'}:
            raise BadRequest('Send one GraphQL request object.')
        query, variables = body.get('query'), body.get('variables') or {}
        if not isinstance(query, str) or not query.strip() or len(query) > MAX_QUERY_CHARS:
            raise BadRequest('Provide a query between 1 and 12000 characters.')
        if not isinstance(variables, dict):
            raise BadRequest('Variables must be an object.')
        operation_name = body.get('operationName')
        if operation_name is not None and not isinstance(operation_name, str):
            raise BadRequest('operationName must be text.')

        document = _check_document(query)
        errors = validate(schema, document)
        if errors:
            return {'errors': [{'message': e.message} for e in errors[:10]]}, 400
    except BadRequest as exc:
        return {'errors': [{'message': str(exc)}]}, 400
    except (GraphQLError, RecursionError) as exc:
        return {'errors': [{'message': getattr(exc, 'message', 'Invalid query.')}]}, 400

    # `request` becomes info.context in every resolver (e.g. info.context.user).
    result = execute_sync(schema, document, context_value=request,
                          variable_values=variables, operation_name=operation_name)
    reply = {'data': result.data}
    if result.errors:
        reply['errors'] = [_error(e) for e in result.errors[:10]]
    return reply, 200


def _error(error):
    """Turn a resolver exception into a message that's safe to show."""
    original = error.original_error
    if isinstance(original, ValidationError):
        return {'message': '; '.join(original.messages), 'extensions': {'code': 'BAD_USER_INPUT'}}
    if original is None:  # GraphQL-level problem, e.g. a bad variable value
        return {'message': error.message, 'extensions': {'code': 'BAD_USER_INPUT'}}
    # Unexpected server error: log it, but never send internals to the client.
    log.error('GraphQL resolver failed', exc_info=original)
    return {'message': 'The request could not be completed.', 'extensions': {'code': 'INTERNAL_ERROR'}}
