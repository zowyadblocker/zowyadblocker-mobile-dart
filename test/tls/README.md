TLS tests generate a fresh localhost certificate and key in a temporary directory
with OpenSSL, then remove that directory after the tests. No private key is kept
in Git or bundled in the application. Only the explicit test SecurityContext
trusts the generated certificate. Git for Windows includes the OpenSSL tool used
by these tests; Linux CI uses the system OpenSSL executable.
