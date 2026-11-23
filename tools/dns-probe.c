/* Independent Android shell-UID test fixture, not application packet processing. */
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

static void fail(const char *message) { perror(message); exit(1); }
static void exact(int fd, unsigned char *b, int n) {
    while (n > 0) { int got = read(fd, b, n); if (got <= 0) fail("TCP read"); b += got; n -= got; }
}
static void probe(int v6, int tcp, const char *name, int expected) {
    int fd = socket(v6 ? AF_INET6 : AF_INET, tcp ? SOCK_STREAM : SOCK_DGRAM, 0);
    if (fd < 0) fail("socket");
    struct timeval timeout = {10, 0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    if (v6) {
        struct sockaddr_in6 a = {.sin6_family = AF_INET6, .sin6_port = htons(53)};
        inet_pton(AF_INET6, "fd00:111::1", &a.sin6_addr);
        if (connect(fd, (struct sockaddr *)&a, sizeof(a))) fail("IPv6 connect");
    } else {
        struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons(53)};
        inet_pton(AF_INET, "10.111.0.1", &a.sin_addr);
        if (connect(fd, (struct sockaddr *)&a, sizeof(a))) fail("IPv4 connect");
    }
    unsigned char q[512] = {0x12, 0x34, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0};
    int len = 12;
    char *copy = strdup(name), *save = NULL;
    for (char *part = strtok_r(copy, ".", &save); part; part = strtok_r(NULL, ".", &save)) {
        int n = strlen(part); if (n > 63 || len + n + 6 > 512) { fprintf(stderr, "Bad fixture name\n"); exit(1); }
        q[len++] = n; memcpy(q + len, part, n); len += n;
    }
    free(copy); q[len++] = 0; q[len++] = 0; q[len++] = 1; q[len++] = 0; q[len++] = 1;
    if (tcp) { unsigned char prefix[2] = {len >> 8, len & 255}; if (write(fd, prefix, 2) != 2) fail("TCP prefix"); }
    if (write(fd, q, len) != len) fail("DNS write");
    unsigned char response[65535]; int got;
    if (tcp) { unsigned char prefix[2]; exact(fd, prefix, 2); got = prefix[0] * 256 + prefix[1]; exact(fd, response, got); }
    else { got = read(fd, response, sizeof(response)); if (got < 0) fail("UDP read"); }
    if (got < 12 || response[0] != 0x12 || response[1] != 0x34 || !(response[2] & 0x80) || (response[3] & 15) != expected) {
        fprintf(stderr, "FAIL IPv%d %s %s: bytes=%d rcode=%d expected=%d\n", v6 ? 6 : 4, tcp ? "TCP" : "UDP", name, got, got >= 4 ? response[3] & 15 : -1, expected); exit(1);
    }
    printf("PASS IPv%d %s %s RCODE=%d bytes=%d\n", v6 ? 6 : 4, tcp ? "TCP" : "UDP", name, expected, got);
    close(fd);
}
int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "temporary-allow")) {
        probe(0, 0, "example.org", 0);
        return 0;
    }
    if (argc == 2 && !strcmp(argv[1], "temporary-undo")) {
        probe(0, 0, "example.org", 3);
        return 0;
    }
    if (argc != 1) return 2;
    for (int v6 = 0; v6 <= 1; v6++) for (int tcp = 0; tcp <= 1; tcp++) {
        probe(v6, tcp, "blocked.zowy.test", 3);
        probe(v6, tcp, "example.com", 0);
    }
    return 0;
}
