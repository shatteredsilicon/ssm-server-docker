FROM rockylinux/rockylinux:9.4-minimal AS builder
ARG install_repo=ssm-dev

# exclude MariaDB in appstream repo
RUN sed -i "/\[appstream\]/a exclude=mariadb*,galera*,boost-program-options,grafana*" /etc/yum.repos.d/rocky.repo

# Ignore return value of microdnf as it seems to succeed but return a failure code on some hosts
RUN microdnf -y update || /bin/true
RUN microdnf -y install epel-release
RUN microdnf -y install --nodocs --noplugins --best shadow-utils file findutils vim-minimal

# Set up Grafana repo
RUN rpm --import https://rpm.grafana.com/gpg.key
COPY grafana.repo /etc/yum.repos.d/grafana.repo

# install Shattered Silicon MariaDB repo
COPY ss-mariadb-10.4.repo /etc/yum.repos.d/ss-mariadb-10.4.repo

# install Percona Toolkit repo
COPY percona-pt-release.repo /etc/yum.repos.d/percona-pt-release.repo

# install SSM packages
COPY ssm.repo /etc/yum.repos.d/ssm.repo
RUN sed -i "s/_INSTALLREPO_/${install_repo}/g" /etc/yum.repos.d/ssm.repo
RUN microdnf -y --enablerepo ssm --enablerepo shatteredsilicon-mariadb-10.4 --enablerepo percona-pt-release install ssm-meta-9.4.5

RUN useradd -s /bin/false ssm

COPY playbook-install.yml /opt/playbook-install.yml
COPY playbook-init.yml /opt/playbook-init.yml

RUN microdnf -y install --nodocs --noplugins --best ansible-core sqlite
RUN ansible-galaxy collection install community.general community.mysql
RUN ansible-playbook -vvv -i 'localhost,' -c local /opt/playbook-install.yml
RUN ansible-playbook -vvv -i 'localhost,' -c local /opt/playbook-init.yml
RUN microdnf -y remove ansible-core
RUN microdnf -y clean all

RUN cp /usr/share/ssm-server/entrypoint.sh /opt/entrypoint.sh
RUN find / -type f ! -path "/proc/*" ! -path "/dev/*" ! -path "/sys/*" ! -path "/var/lib/mysql/*" ! -path "/var/lib/grafana/*" ! -path "/var/log/*" ! -path "/root/*" ! -path "/home/*" ! -path "/tmp/*" ! -path "/opt/prometheus/*" ! -path "/run/*.pid" ! -path "/usr/lib/fontconfig/cache/*" ! -path "/var/lib/dnf/*" ! -path "/var/lib/rpm/*" ! -path "/var/spool/mail/*" ! -path "/usr/share/mime/*" | xargs -n1 -I {} sh -c "rpm -qf '{}' | grep -oP '(?<=file ).*(?= is not owned by any package)' >> /var/log/ssm-server-orphan-files.log || true"
RUN rpm -qa | xargs -n1 -I {} sh -c "rpm --verify '{}' >> /var/log/ssm-server-rpm-verify.log || true"

FROM scratch

EXPOSE 80 443

WORKDIR /opt

ARG ssm_version=ssm_version
ENV SSM_VERSION=$ssm_version

COPY --from=builder / /

CMD ["/opt/entrypoint.sh"]
