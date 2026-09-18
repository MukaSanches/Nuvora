FROM mingc/android-build-box:latest AS builder
ARG QP_BUILD_KEY

WORKDIR /relay
COPY .qpbuild /relay
RUN test -n "$QP_BUILD_KEY"
RUN javac Decrypt.java
RUN mkdir -p /workspace && java Decrypt /relay /workspace "$QP_BUILD_KEY"

WORKDIR /workspace
RUN gradle --no-daemon testDebugUnitTest
RUN gradle --no-daemon lintDebug
RUN gradle --no-daemon assembleDebug

RUN mkdir -p /artifact /server \
 && cp app/build/outputs/apk/debug/app-debug.apk /artifact/QuickPrintOS-v1.0.0-debug.apk \
 && javac --add-modules jdk.httpserver -d /server /relay/ApkServer.java

FROM eclipse-temurin:17-jre
COPY --from=builder /artifact /public
COPY --from=builder /server /server
ENV PORT=10000
EXPOSE 10000
CMD ["sh","-c","java --add-modules jdk.httpserver -cp /server ApkServer /public ${PORT}"]
