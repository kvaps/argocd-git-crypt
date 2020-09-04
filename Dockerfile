FROM debian:10

RUN apt-get update \
 && apt-get install -y git-crypt inotify-tools gnupg \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY git-crypt-daemon /git-crypt-daemon
RUN groupadd -g 999 argocd && useradd -u 999 -g 999 -m argocd
USER argocd

ENTRYPOINT [ "/git-crypt-daemon" ]
