"""Authentication module."""

from functools import wraps

from flask import Response, current_app, request


def valid_brearer_token():
    """Validate the bearer token."""
    service_api_key = current_app.config["SERVICE_API_KEY"]
    return request.authorization and request.authorization.token == service_api_key


def require_auth(func):
    """Require authentication for the given route."""

    @wraps(func)
    def wrapper(*args, **kwargs):
        """Wrapper function return Unauthorized if the token is invalid."""
        if valid_brearer_token():
            return func(*args, **kwargs)
        else:
            return Response("Unauthorized", 401)

    return wrapper
