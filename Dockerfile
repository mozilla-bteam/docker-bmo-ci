FROM mozillabteam/bmo-base:latest
MAINTAINER Dylan Hardison <dylan@mozilla.com>, David Lawrence <dkl@mozilla.com>

RUN rsync -a /opt/bmo/local/lib/perl5/x86_64-linux-thread-multi/ /usr/local/lib64/perl5/ && \
    rsync -a --exclude x86_64-linux-thread-multi/ \
        /opt/bmo/local/lib/perl5/ /usr/local/share/perl5/

# Environment configuration
ENV BUGS_DB_DRIVER mysql
ENV BUGS_DB_NAME bugs

ENV BUGZILLA_USER bugzilla
ENV BUGZILLA_ROOT /var/www/html/bmo

ENV GITHUB_BASE_GIT https://github.com/mozilla-bteam/bmo
ENV GITHUB_BASE_BRANCH master
ENV PATCH_DIR /patch_dir
ENV BUGZILLA_UNSAFE_AUTH_DELEGATION 1

# User configuration
RUN useradd -m -G wheel -u 1000 -s /bin/bash $BUGZILLA_USER \
    && passwd -u -f $BUGZILLA_USER \
    && echo "bugzilla:bugzilla" | chpasswd

# Apache configuration
COPY conf/bugzilla.conf /etc/httpd/conf.d/bugzilla.conf

# MySQL configuration
COPY conf/my.cnf /etc/my.cnf
RUN chmod 644 /etc/my.cnf \
    && chown root.root /etc/my.cnf \
    && rm -vrf /etc/mysql \
    && rm -vrf /var/lib/mysql/*

RUN /usr/bin/mysql_install_db --user=$BUGZILLA_USER --basedir=/usr --datadir=/var/lib/mysql

# Copy setup and test scripts
COPY scripts/* /usr/local/bin/
RUN chmod 755 /usr/local/bin/*

# Testing scripts for CI
ADD https://selenium-release.storage.googleapis.com/2.53/selenium-server-standalone-2.53.1.jar /selenium-server.jar

# Networking
RUN echo "NETWORKING=yes" > /etc/sysconfig/network
EXPOSE 80
EXPOSE 5900

CMD ["runtests.sh"]
