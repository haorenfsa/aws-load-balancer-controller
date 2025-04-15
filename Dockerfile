# syntax=docker/dockerfile:experimental

ARG BASE_IMAGE=public.ecr.aws/eks-distro-build-tooling/eks-distro-minimal-base-nonroot:2024-08-13-1723575672.2
ARG BUILD_IMAGE=public.ecr.aws/docker/library/golang:1.23.6

FROM $BUILD_IMAGE AS base
WORKDIR /workspace
# Copy the Go Modules manifests
COPY go.mod go.mod
COPY go.sum go.sum
# Copy the go source
COPY main.go main.go
COPY pkg ./pkg
COPY controllers ./controllers
COPY apis ./apis
COPY webhooks ./webhooks

# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN --mount=type=bind,target=. \
    go mod download

FROM base AS build
ARG TARGETOS=linux
ARG TARGETARCH=amd64
ENV VERSION_PKG=sigs.k8s.io/aws-load-balancer-controller/pkg/version
RUN --mount=type=bind,target=. \
    --mount=type=cache,target=/root/.cache/go-build \
    VERSION=2.12.111 && \
    BUILD_DATE=$(date +%Y-%m-%dT%H:%M:%S%z) && \
    GOOS=${TARGETOS} GOARCH=${TARGETARCH} GO111MODULE=on \
    CGO_CPPFLAGS="-D_FORTIFY_SOURCE=2" \
    CGO_LDFLAGS="-Wl,-z,relro,-z,now" \
    go build -buildmode=pie -tags 'osusergo,netgo,static_build' -ldflags="-s -w -linkmode=external -extldflags '-static-pie' -X ${VERSION_PKG}.GitVersion=${VERSION} -X ${VERSION_PKG}.BuildDate=${BUILD_DATE}" -a -o /out/controller main.go

FROM $BASE_IMAGE as bin-unix

COPY --from=build /out/controller /controller
ENTRYPOINT ["/controller"]
