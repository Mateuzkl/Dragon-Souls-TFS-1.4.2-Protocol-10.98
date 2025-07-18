FROM alpine:3.19.0 AS build
RUN apk add --no-cache \
  build-base \
  boost-dev \
  cmake \
  fmt-dev \
  luajit-dev \
  mariadb-connector-c-dev \
  openssl-dev \
  pugixml-dev \
  samurai

COPY cmake /usr/src/forgottenserver/cmake/
COPY src /usr/src/forgottenserver/src/
COPY CMakeLists.txt CMakePresets.json /usr/src/forgottenserver/
WORKDIR /usr/src/forgottenserver
RUN cmake --preset default && cmake --build --config RelWithDebInfo --preset default

FROM alpine:3.19.0
RUN apk add --no-cache \
  boost-iostreams \
  boost-locale \
  boost-system \
  fmt \
  luajit \
  mariadb-connector-c \
  openssl \
  pugixml

COPY --from=build /usr/src/forgottenserver/build/RelWithDebInfo/tfs /bin/tfs
COPY data /srv/data/
COPY LICENSE README.md *.dist *.sql key.pem /srv/

EXPOSE 7171 7172
WORKDIR /srv
VOLUME /srv
ENTRYPOINT ["/bin/tfs"]
