FROM registry.access.redhat.com/openshift3/rhel7-base:latest

ADD repo/* /etc/yum.repos.d/
RUN INSTALL_PKGS="gettext automake make docker" && \
    yum install -y $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    yum clean all &&\
    rm -rf /etc/yum.repos.d/*

LABEL io.k8s.display-name="OpenShift Custom Builder Example" \
      io.k8s.description="This is an example of a custom builder for use with OpenShift."
ENV HOME=/root
COPY build.sh /tmp/build.sh
CMD ["/tmp/build.sh"]
