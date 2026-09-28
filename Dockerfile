# The Hacker's Diet Online (John Walker, fourmilab.ch) as an Apache CGI app.
#
# The Perl code has absolute paths baked in, so the container reproduces
# the original server layout instead of patching the source:
#   /server/bin/httpd/cgi-bin   CGI programs + HDiet/ modules
#   /server/pub/hackdiet        user database (mount a volume here)
#   /hackdiet/online            static files (URL path, served by Apache)
FROM debian:bookworm-slim

LABEL org.opencontainers.image.title="The Hacker's Diet Online" \
      org.opencontainers.image.description="John Walker's Hacker's Diet Online weight tracker, packaged as a container" \
      org.opencontainers.image.source="https://github.com/andreashouben/hackdiet_online" \
      org.opencontainers.image.licenses="CC0-1.0"

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        apache2 \
        perl \
        libgd-perl \
        libxml-libxml-perl \
        libcrypt-cbc-perl \
        libcgi-pm-perl \
        libssl3 \
        zip bzip2 bind9-dnsutils \
        busybox-syslogd \
        fonts-liberation2 \
 && buildDeps='build-essential libssl-dev cpanminus' \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $buildDeps \
 && cpanm --notest Digest::SHA1@2.13 Crypt::OpenSSL::AES@0.23 \
 && apt-get purge -y --auto-remove $buildDeps \
 && rm -rf /var/lib/apt/lists/* /root/.cpanm \
 && a2enmod cgid alias >/dev/null \
 && echo "ServerName localhost" > /etc/apache2/conf-enabled/servername.conf

# CGI programs and Perl modules
COPY HackDiet.pl      /server/bin/httpd/cgi-bin/HackDiet
COPY HackDietBadge.pl /server/bin/httpd/cgi-bin/HackDietBadge
COPY HDiet/           /server/bin/httpd/cgi-bin/HDiet/

# Static web content
COPY webapp.html hdiet.css hdiet_handheld.css hdiet.js hackersdiet.dtd \
     hackdiet_db.css wz_jsgraphics.js /server/web/hackdiet/online/
COPY figures/ /server/web/hackdiet/online/figures/

COPY docker/hackdiet.conf  /etc/apache2/sites-available/000-default.conf
COPY docker/entrypoint.sh  /usr/local/bin/entrypoint.sh

# The charts use "Times"; the original Times New Roman is not
# redistributable, Liberation Serif is metric-compatible (SIL OFL).
RUN ln -s /usr/share/fonts/truetype/liberation2/LiberationSerif-Regular.ttf \
          /server/bin/httpd/cgi-bin/HDiet/Fonts/Times.ttf \
 && chmod 755 /server/bin/httpd/cgi-bin/HackDiet \
              /server/bin/httpd/cgi-bin/HackDietBadge \
              /usr/local/bin/entrypoint.sh \
 && mkdir -p /server/pub/hackdiet \
 && test -r /server/bin/httpd/cgi-bin/HDiet/Fonts/Times.ttf \
 && perl -I/server/bin/httpd/cgi-bin -c /server/bin/httpd/cgi-bin/HackDiet \
 && perl -I/server/bin/httpd/cgi-bin -c /server/bin/httpd/cgi-bin/HackDietBadge

VOLUME /server/pub/hackdiet
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --start-interval=2s \
    CMD busybox wget -qO /dev/null http://127.0.0.1/cgi-bin/HackDiet || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
