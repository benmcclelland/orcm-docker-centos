FROM centos:centos6

MAINTAINER Ben McClelland <ben.mcclelland@gmail.com>

RUN yum update -y
RUN yum install -y wget unzip tar git gcc m4 gcc-c++ make flex libtool-ltdl openssl \
                   openssl-devel sigar sigar-devel unixODBC unixODBC-devel xz patch \
                   rpm-build libtool

ENV PATH /usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin:/opt/open-rcm/bin
ENV LD_LIBRARY_PATH /opt/open-rcm/lib

RUN wget http://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.xz && \
    tar xf autoconf-2.69.tar.xz && cd autoconf-2.69 && \
    ./configure --prefix=/usr/local && make && make install && \
    cd .. && rm -rf autoconf-2.69*

RUN wget http://ftp.gnu.org/gnu/automake/automake-1.12.2.tar.xz && \
    tar xf automake-1.12.2.tar.xz && cd automake-1.12.2 && \
    ./configure --prefix=/usr/local && make && make install && \
    cd .. && rm -rf automake-1.12.2*

RUN wget http://ftp.gnu.org/gnu/libtool/libtool-2.4.2.tar.xz && \
    tar xf libtool-2.4.2.tar.xz && cd libtool-2.4.2 && \
    ./configure --prefix=/usr/local && make && make install && \
    cd .. && rm -rf libtool-2.4.2*

RUN wget http://ipmiutil.sourceforge.net/FILES/archive/ipmiutil-2.9.4-1.src.rpm && \
    rpmbuild --rebuild --define "_topdir /root/rpmbuild" ipmiutil-2.9.4-1.src.rpm && \
    rm -f ipmiutil-2.9.4* && \
    yum -y localinstall /root/rpmbuild/RPMS/x86_64/ipmiutil-2.9.4-1.el6.x86_64.rpm \
                        /root/rpmbuild/RPMS/x86_64/ipmiutil-devel-2.9.4-1.el6.x86_64.rpm

RUN git clone https://github.com/open-mpi/orcm.git && \
    cd orcm && \
    mkdir -p /opt/open-rcm && \
    ./autogen.pl && \
    ./configure --prefix=/opt/open-rcm \
                --with-platform=./contrib/platform/intel/hillsboro/orcm-linux && \
    make -j 4 && \
    make install

ADD orcm-site.xml /opt/open-rcm/etc/orcm-site.xml

RUN yum localinstall -y http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm && \
    yum install -y sudo

RUN perl -pi -e "s:Defaults    requiretty:#Defaults    requiretty:" /etc/sudoers

RUN yum localinstall -y http://yum.postgresql.org/9.3/redhat/rhel-6-x86_64/pgdg-centos93-9.3-1.noarch.rpm && \
    yum install -y postgresql93-server postgresql93-odbc && \
    /etc/init.d/postgresql-9.3 initdb

EXPOSE 55805 55820 5432 12345 12346 12347 12348 12349 12350

RUN perl -pi -e "s:<Path to the PostgreSQL ODBC driver>:$(rpm -ql postgresql93-odbc | grep psqlodbc.so):" orcm/contrib/database/psql_odbc_driver.ini && \
    odbcinst -i -d -f orcm/contrib/database/psql_odbc_driver.ini && \
    perl -pi -e "s:<Name of the PostgreSQL driver>:$(rpm -ql postgresql93-odbc | grep psqlodbc.so):" orcm/contrib/database/orcmdb_psql.ini && \
    perl -pi -e "s:<Name or IP address of the database server>:db:" orcm/contrib/database/orcmdb_psql.ini && \
    odbcinst -i -s -f orcm/contrib/database/orcmdb_psql.ini -h

ADD pg_hba.conf /var/lib/pgsql/9.3/data/pg_hba.conf
ADD postgresql.conf /var/lib/pgsql/9.3/data/postgresql.conf

RUN /etc/init.d/postgresql-9.3 start && \
    sudo -u postgres psql --command "CREATE USER orcmuser WITH SUPERUSER PASSWORD 'orcmpassword';" && \
    sudo -u postgres createdb -O orcmuser orcmdb && \
    sudo -u postgres psql --username=orcmuser --dbname=orcmdb -f orcm/contrib/database/orcmdb_psql.sql
