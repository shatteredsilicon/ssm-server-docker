FROM rockylinux:9.3-minimal AS builder

# exclude MariaDB in appstream repo
RUN sed -i "/\[appstream\]/a exclude=mariadb*,galera*,boost-program-options" /etc/yum.repos.d/rocky.repo

RUN microdnf -y update && \
    microdnf -y install epel-release && \
    microdnf -y install --nodocs --noplugins --best shadow-utils file && \
    microdnf -y clean all

# install SSM packages
COPY ssm.repo /etc/yum.repos.d/ssm.repo
RUN microdnf -y --enablerepo ssm install ssm-meta-9.3.0

RUN useradd -s /bin/false ssm

COPY playbook-install.yml /opt/playbook-install.yml
COPY playbook-init.yml /opt/playbook-init.yml

RUN microdnf -y install --nodocs --noplugins --best ansible-core sqlite && \
    ansible-galaxy collection install community.general community.mysql && \
    ansible-playbook -vvv -i 'localhost,' -c local /opt/playbook-install.yml && \
    ansible-playbook -vvv -i 'localhost,' -c local /opt/playbook-init.yml && \
    microdnf -y remove ansible-core && microdnf -y clean all

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