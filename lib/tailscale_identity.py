"""websockify auth plugin that admits only allowed Tailscale identities.

`tailscale serve` adds a Tailscale-User-Login header to proxied requests.
The auth source is a comma-separated list of allowed login names.
"""

from websockify.auth_plugins import AuthenticationError


class TailscaleIdentity:
    def __init__(self, src=None):
        self.allowed = {login.strip().lower()
                        for login in (src or '').split(',') if login.strip()}

    def authenticate(self, headers, target_host, target_port):
        login = (headers.get('Tailscale-User-Login') or '').strip().lower()
        if not login or login not in self.allowed:
            raise AuthenticationError(
                log_msg='Rejected Tailscale identity %r' % login,
                response_msg='Forbidden')
