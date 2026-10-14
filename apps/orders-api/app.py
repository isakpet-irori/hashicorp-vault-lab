import os
import ssl
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


TLS_BUNDLE_PATH = os.environ.get("TLS_BUNDLE_PATH", "")
TLS_CERT_PATH = os.environ.get("TLS_CERT_PATH", "/etc/orders-api/tls.crt")
TLS_KEY_PATH = os.environ.get("TLS_KEY_PATH", "/etc/orders-api/tls.key")
CONFIG_PATH = Path(os.environ.get("ORDERS_CONFIG_PATH", "/vault/secrets/orders-config"))


def load_tls_context():
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    if TLS_BUNDLE_PATH:
        context.load_cert_chain(TLS_BUNDLE_PATH)
    else:
        context.load_cert_chain(TLS_CERT_PATH, TLS_KEY_PATH)
    return context


class OrdersHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def do_GET(self):
        path = urlsplit(self.path).path

        if path == "/healthz":
            self.send_text(200, "ok\n")
        elif path == "/":
            self.send_text(200, "orders-api HTTPS app is running\n")
        elif path == "/config":
            try:
                config = CONFIG_PATH.read_text()
            except FileNotFoundError:
                self.send_text(503, "Vault configuration is not ready\n")
            else:
                self.send_text(200, config)
        else:
            self.send_text(404, "not found\n")

    def send_text(self, status, body):
        payload = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, format_string, *args):
        print(f"{self.client_address[0]} - {format_string % args}", flush=True)


class ReloadingTLSServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def get_request(self):
        connection, address = super().get_request()
        try:
            tls_connection = load_tls_context().wrap_socket(
                connection,
                server_side=True,
            )
        except (OSError, ssl.SSLError):
            connection.close()
            raise
        return tls_connection, address


def wait_for_certificate():
    while True:
        try:
            load_tls_context()
            return
        except (OSError, ssl.SSLError):
            time.sleep(1)


def main():
    wait_for_certificate()
    with ReloadingTLSServer(("0.0.0.0", 8443), OrdersHandler) as server:
        print("orders-api HTTPS server listening on port 8443", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
