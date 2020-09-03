FROM alpine:3.12

RUN apk add --no-cache git-crypt inotify-tools sed gnupg
COPY git-crypt-inotify /git-crypt-inotify

ENTRYPOINT [ "/git-crypt-inotify" ]
