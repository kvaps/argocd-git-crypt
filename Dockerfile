FROM alpine:3.12

RUN apk add --no-cache git-crypt inotify-tools sed gnupg
COPY git-crypt-daemon /git-crypt-daemon
RUN delgroup ping; adduser -u 999 argocd -D
USER argocd

ENTRYPOINT [ "/git-crypt-daemon" ]
