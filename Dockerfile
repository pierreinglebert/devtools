FROM ubuntu:disco AS base_devtools

RUN sed -i 's|http://archive|http://fr.archive|g' /etc/apt/sources.list

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
        build-essential \
        cmake \
        curl \
        git \
        gcc \
        ninja-build \
        g++ \
        libc-dev \
        perl \
        unzip \
        tar \
        linux-tools-common \
        linux-tools-virtual \
        linux-tools-generic


FROM base_devtools AS with_vcpkg

WORKDIR /opt
RUN git clone https://github.com/Microsoft/vcpkg.git
WORKDIR /opt/vcpkg

RUN ./bootstrap-vcpkg.sh --useSystemBinaries

RUN ./vcpkg install --triplet x64-linux grpc curlpp nlohmann-json benchmark

##################################################################################
####### Devtools
##################################################################################

FROM base_devtools AS devtools
WORKDIR /opt/
RUN git clone https://github.com/Microsoft/vcpkg.git
COPY --from=with_vcpkg /opt/vcpkg/installed /opt/vcpkg/installed
COPY --from=with_vcpkg /opt/vcpkg/vcpkg /opt/vcpkg

# Printout the installed packages, serves as verification that vcpkg is
# functional.
RUN /opt/vcpkg/vcpkg list

RUN curl http://mirrors.ocf.berkeley.edu/gnu/gcc/gcc-9.1.0/gcc-9.1.0.tar.gz -o gcc-9.1.0.tar.gz
RUN tar xf gcc-9.1.0.tar.gz
WORKDIR /opt/gcc-9.1.0
RUN contrib/download_prerequisites

RUN mkdir /opt/build
WORKDIR /opt/build
RUN ../gcc-9.1.0/configure -v --build=x86_64-linux-gnu --host=x86_64-linux-gnu --target=x86_64-linux-gnu --prefix=/usr/local/gcc-9.1 --enable-checking=release --enable-languages=c,c++,fortran --disable-multilib --program-suffix=-9.1
RUN make -j 4
RUN make install

##################################################################################
####### Remote devtools
##################################################################################

FROM devtools AS remote_devtools

RUN apt-get update  && apt-get install -y \
    apt-utils gcc g++ openssh-server cmake build-essential gdb gdbserver rsync vim python-minimal

COPY tools/cmake_wrapper.py /usr/bin
RUN chmod +x /usr/bin/cmake_wrapper.py

RUN mkdir /var/run/sshd
RUN echo 'root:root' | chpasswd
RUN sed -i 's/PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/#MaxSessions 10/MaxSessions 1000/' /etc/ssh/sshd_config
RUN sed -i 's/#MaxStartups 10:30:60/MaxSessions 1000:30:2000/' /etc/ssh/sshd_config


# SSH login fix. Otherwise user is kicked off after login
RUN sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

ENV NOTVISIBLE "in users profile"
RUN echo "export VISIBLE=now" >> /etc/profile

# 22 for ssh server. 7777 for gdb server.
EXPOSE 22 7777

RUN useradd -ms /bin/bash debugger
RUN echo 'debugger:pwd' | chpasswd

RUN chown -R debugger /opt

CMD ["/usr/sbin/sshd", "-D"]
