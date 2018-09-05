FROM cockroachdb/cockroach:latest

MAINTAINER Lucas Teske <lucas@teske.com.br>

RUN apt-get update && apt-get -y install curl dnsutils

COPY run.sh /cockroach

VOLUME ["/cockroach/cockroach-data/cockroach"]
ENTRYPOINT ["/cockroach/run.sh"]
