set -e

yum -y update

systemctl disable postfix
systemctl stop postfix

echo "Installing and setting up network-priority performance profile"
    yum -y install tuned
    tuned-adm profile latency-performance
    tuned-adm active

echo "Installing Cockpit and removing its version of docker from under it (Kargo wants a different one)"
    rpm -q cockpit || (yum -y install cockpit cockpit-docker cockpit-kubernetes cockpit-pcp cockpit-dashboard cockpit-machines cockpit-bridge cockpit-storaged cockpit-system)
    systemctl enable cockpit.service
    systemctl start cockpit.service
    rpm -e --nodeps docker-client || true
    rpm -e --nodeps docker || true
    rpm -e --nodeps docker-common || true

export GOPATH="/usr/local/go"

echo "Setting network performance parameters"
    cat <<-THE_END >> /etc/sysctl.conf
        vm.max_map_count=262144
        net.ipv4.ip_local_port_range=16384     60999
        net.ipv4.tcp_fin_timeout=15
        net.ipv4.tcp_tw_recycle=1
        net.ipv4.tcp_tw_reuse=1
        net.ipv4.ip_forward=1
        net.core.somaxconn=65535
        net.core.netdev_max_backlog=4096
        net.ipv4.tcp_max_syn_backlog=4096
THE_END

    sysctl -p /etc/sysctl.conf

    echo >> /etc/rc.local
    echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' >> /etc/rc.local
    echo 'sysctl -p /etc/sysctl.conf' >> /etc/rc.local

    cat <<-THE_END > /etc/security/limits.conf
        * soft nofile 65535
        * hard nofile 65535
THE_END

    INTERFACES="$(ifconfig | awk '{ print $1; }' | grep -E '(ens|eth)[0-9]+:' | sed s/://)"
    for INTERFACE in $INTERFACES; do
        echo "/sbin/ifconfig '$INTERFACE' txqueuelen 5000" >> /etc/rc.local
        /sbin/ifconfig "$INTERFACE" txqueuelen 5000
    done

echo "Setting up Python environment for Ansible/Kargo"
    yum -y install epel-release
    yum -y install git ansible python34 python34-pip python2-pip python-jinja2 jq httpd-tools patch fping
    pip install --upgrade pip
    pip3 install --upgrade pip
    pip2 install netaddr
    pip3 install netaddr

    # ansible's 'equalto' command requires jinja2 2.8 or higher; OOB we get 2.7.2.
    pip2 install --upgrade jinja2
    pip3 install --upgrade jinja2

    # This is pinned at a super old version
    rpm -e --nodeps kubernetes-client || true
    curl -o /usr/local/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/v1.7.1/bin/linux/amd64/kubectl
    chmod +x /usr/local/bin/kubectl

echo "Installing Ceph repo and ceph command line"
        cat <<-THE_END > /etc/yum.repos.d/ceph.repo
            [ceph-noarch]
            name="Ceph noarch packages"
            baseurl=http://download.ceph.com/rpm-jewel/el7/x86_64
            enabled=1
            gpgcheck=1
            type=rpm-md
            gpgkey=https://ceph.com/git/?p=ceph.git;a=blob_plain;f=keys/release.asc
THE_END

        sed -i'' 's/^ *//g' /etc/yum.repos.d/ceph.repo

        yum -y install ceph
        echo > /etc/modprobe.d/rbd.conf
        modprobe rbd

# Redhat/CentOS Go is busted - https://bugzilla.redhat.com/show_bug.cgi?id=1379484f
# We're using the suggestion of Travis-CI's "gimme" installer from
# https://github.com/kubernetes/kubernetes/issues/29534 at
# https://github.com/travis-ci/gimme
echo "Setting up Go"
    # Slacker's way to ensure deps
    yum -y install go && yum -y remove go
    mkdir -p "$GOPATH"
    curl -sL -o /usr/local/bin/gimme https://raw.githubusercontent.com/travis-ci/gimme/master/gimme
    chmod +x /usr/local/bin/gimme
    GIMME_VERSION_PREFIX=/usr/local/gimme/versions GIMME_ENV_PREFIX=/usr/local/gimme/env /usr/local/bin/gimme 1.7.3

    # Minimizes screwing with the path
    yes | cp -a /usr/local/gimme/versions/go1.7.3*/bin/* /usr/local/bin/

    cat <<-'THE_END' > /etc/profile.d/go-paths.sh
        unset GOOS;
        unset GOARCH;
        export GOROOT="$(ls -d /usr/local/gimme/versions/go1.7.3*)";
        /usr/local/bin/go version >&2;
        export GOPATH=/usr/local/go
        export PATH="$PATH:/usr/local/go/bin:/usr/local/bin"
THE_END

    chmod +x /etc/profile.d/go-paths.sh

    . /etc/profile.d/go-paths.sh

    yum -y remove epel-release

reboot
exit 0