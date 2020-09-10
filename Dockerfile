FROM argoproj/argocd:v1.7.3

USER root

RUN apt-get update \
 && apt-get install -y git-crypt \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN mv /usr/bin/git /usr/bin/git.bin
COPY git /usr/bin/git

USER argocd
