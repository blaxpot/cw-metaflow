FROM debian:latest as build

RUN apt-get update &&  \
    apt-get install -y ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

RUN curl -O https://s3.amazonaws.com/amazoncloudwatch-agent/debian/amd64/latest/amazon-cloudwatch-agent.deb && \
    dpkg -i -E amazon-cloudwatch-agent.deb && \
    rm -rf /tmp/* && \
    rm -rf /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard && \
    rm -rf /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl && \
    rm -rf /opt/aws/amazon-cloudwatch-agent/bin/config-downloader

FROM python:3.12.4-slim-bullseye

RUN apt-get update \
    && apt-get install -y jq\
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /tmp /tmp
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /opt/aws/amazon-cloudwatch-agent /opt/aws/amazon-cloudwatch-agent
COPY amazon-cloudwatch-agent.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
RUN chmod a+r /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
RUN useradd -m -u 1000 -s /bin/sh metaflow
RUN mkdir /logs && chown 1000 /logs
RUN mkdir /metaflow
COPY entrypoint.sh /metaflow/entrypoint.sh
RUN chmod a+x /metaflow/entrypoint.sh
RUN chown -R 1000 /metaflow
ENV HOME=/metaflow
WORKDIR /metaflow

# We can't specify CMD as it's overwritten by Metaflow, but ENTRYPOINT should work to run the CW agent if we're careful.
# See: https://outerbounds.com/docs/build-custom-image/#using-entrypoint-and-cmd
ENTRYPOINT ["/metaflow/entrypoint.sh"]
