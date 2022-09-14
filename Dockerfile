FROM quay.io/centos/centos:stream8


RUN yum -y update \
    && yum -y install gcc-c++ git make cmake libatomic wget  \
    && yum -y install sudo && yum -y install python3 \
    && yum -y install epel-release \
    && yum -y install gperftools gperftools-devel \
    && yum clean all

RUN sudo yum -y install boost-devel \
    && sudo yum -y install openssl-devel \
    && sudo yum -y install protobuf \
    && sudo yum -y install unzip


RUN sudo yum -y install autoconf libtool \
    && sudo yum -y install pkgconfig

RUN  git clone https://github.com/microsoft/cpprestsdk.git \
    && cd cpprestsdk \
     && mkdir build && cd build \
     && cmake .. -DCPPREST_EXCLUDE_WEBSOCKETS=ON \
     && make -j$(nproc) && sudo make install

RUN git clone --progress -b v3.10.0 https://github.com/protocolbuffers/protobuf && \
        ( \
          cd protobuf; \
          mkdir build; \
          cd build; \
          cmake ../cmake \
            -DCMAKE_BUILD_TYPE=Release \
            -Dprotobuf_BUILD_SHARED_LIBS=ON \
            -Dprotobuf_BUILD_TESTS=OFF; \
          sudo cmake --build . --config Release --target install; \
          sudo make -j4 install; \
        ) && rm -rf protobuf

RUN cd /home && wget -c http://downloads.sourceforge.net/project/boost/boost/1.66.0/boost_1_66_0.tar.gz \
  && tar xfz boost_1_66_0.tar.gz \
  && rm boost_1_66_0.tar.gz \
  && cd boost_1_66_0 \
  && ./bootstrap.sh --prefix=/usr/local --with-libraries=program_options,system,filesystem,regex,log,serialization,random \
  && ./b2 install \
  && cd /home \
  && rm -rf boost_1_66_0

RUN sudo yum -y groups mark install "Development Tools" \
    && sudo yum -y groupinstall "Development Tools" \
    && sudo yum -y install autoconf libtool \
    && sudo yum -y install pkgconfig \
    && git clone --recurse-submodules -b v1.46.3 --depth 1 --shallow-submodules https://github.com/grpc/grpc \
    && cd grpc \
    && mkdir -p cmake/build \
    && pushd cmake/build \
    && cmake -DgRPC_INSTALL=ON -DgRPC_BUILD_TESTS=OFF ../.. \
    && make -j \
    && sudo make install

#ENV PATH="${PATH}:${HOME}/.local/bin"
RUN git clone https://github.com/etcd-cpp-apiv3/etcd-cpp-apiv3.git \
    && cd etcd-cpp-apiv3 \
    && mkdir build && cd build \
    && cmake .. \
    && sudo make -j$(nproc) && sudo make install
ADD . /test

WORKDIR /test/build
RUN cmake ..
RUN make


ENTRYPOINT ["/bin/bash"]
