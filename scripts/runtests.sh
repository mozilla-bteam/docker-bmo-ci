#!/bin/bash -e
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

if [ -z "$TEST_SUITE" ]; then
    TEST_SUITE=sanity
fi

# Output to log file as well as STDOUT/STDERR
exec > >(tee /var/log/runtests.log) 2>&1

echo "== Retrieving Bugzilla code"
echo "Checking out $GITHUB_BASE_GIT $GITHUB_BASE_BRANCH ..."
git clone $GITHUB_BASE_GIT --branch $GITHUB_BASE_BRANCH $BUGZILLA_ROOT
cd $BUGZILLA_ROOT
ln -s /opt/bmo/local $BUGZILLA_ROOT/local
if [ "$GITHUB_BASE_REV" != "" ]; then
    echo "Switching to revision $GITHUB_BASE_REV ..."
    git checkout -q $GITHUB_BASE_REV
fi

chown -R $BUGZILLA_USER.$BUGZILLA_USER $BUGZILLA_ROOT

if [ "$TEST_SUITE" = "sanity" ]; then
    buildbot_step "Sanity" prove -f -v t/*.t
    exit $?
fi

if [ "$TEST_SUITE" = "docs" ]; then
    cd $BUGZILLA_ROOT/docs
    buildbot_step "Documentation" perl makedocs.pl --with-pdf
    exit $?
fi

echo -e "\n== Starting database"
/usr/bin/mysqld_safe &
sleep 10

echo -e "\n== Starting memcached"
/usr/bin/memcached -u memcached -d
sleep 10

echo -e "\n== Updating configuration"
mysql -u root mysql -e "GRANT ALL PRIVILEGES ON *.* TO bugs@localhost IDENTIFIED BY 'bugs'; FLUSH PRIVILEGES;" || exit 1
mysql -u root mysql -e "CREATE DATABASE bugs_test CHARACTER SET = 'utf8';" || exit 1
mysql -u root mysql -e "GRANT ALL PRIVILEGES ON bugs_test.* TO bugs@'%' IDENTIFIED BY 'bugs'; FLUSH PRIVILEGES;" || exit 1
sed -e "s?%DB%?$BUGS_DB_DRIVER?g" --in-place $BUGZILLA_ROOT/qa/config/checksetup_answers.txt
sed -e "s?%DB_NAME%?bugs_test?g" --in-place $BUGZILLA_ROOT/qa/config/checksetup_answers.txt
sed -e "s?%USER%?$BUGZILLA_USER?g" --in-place $BUGZILLA_ROOT/qa/config/checksetup_answers.txt
echo "\$answer{'memcached_servers'} = 'localhost:11211';" >> $BUGZILLA_ROOT/qa/config/checksetup_answers.txt
patch -p1 < /selenium_conf.patch

echo -e "\n== Running checksetup"
cd $BUGZILLA_ROOT
./checksetup.pl qa/config/checksetup_answers.txt
./checksetup.pl qa/config/checksetup_answers.txt

echo -e "\n== Generating bmo data"
generate_bmo_data.pl

echo -e "\n== Generating test data"
cd $BUGZILLA_ROOT/qa/config
perl generate_test_data.pl

echo -e "\n== Starting web server"
perl -i -pe 's/^User apache/User bugzilla/' /etc/httpd/conf/httpd.conf
perl -i -pe 's/^Group apache/Group bugzilla/' /etc/httpd/conf/httpd.conf
/usr/sbin/httpd &
sleep 10

cd $BUGZILLA_ROOT/qa/t

if [ "$TEST_SUITE" = "selenium" ]; then
    export DISPLAY=:0

    # Setup dbus for Firefox
    dbus-uuidgen > /var/lib/dbus/machine-id

    echo -e "\n== Starting virtual frame buffer and vnc server"
    Xvnc $DISPLAY -screen 0 1280x1024x16 -ac -SecurityTypes=None \
         -extension RANDR 2>&1 | tee /xvnc.log &
    sleep 5

    echo -e "\n== Starting Selenium server"
    java -jar /selenium-server.jar -log /selenium.log > /dev/null 2>&1 &
    sleep 5

    # Set NO_TESTS=1 if just want selenium services
    # but no tests actually executed.
    [ $NO_TESTS ] && exit 0

    buildbot_step "Selenium" prove -f -v -I$BUGZILLA_ROOT/lib test_*.t
    exit $?
fi

if [ "$TEST_SUITE" = "webservices" ]; then
    buildbot_step "Webservices" prove -f -v -I$BUGZILLA_ROOT/lib webservice_*.t
    exit $?
fi
