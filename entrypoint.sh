#!/bin/bash
# Use bash parameter expansion to get the flow name from Metaflow's S3 env vars
METAFLOW_CODE_PATH=${METAFLOW_CODE_URL#"${METAFLOW_DATASTORE_SYSROOT_S3}/"}
FLOW_NAME="${METAFLOW_CODE_PATH%%/*}"

# Set a default value for FLOW_NAME if the Metaflow env vars aren't present
FLOW_NAME=${FLOW_NAME:-UnknownFlow}

# Update the metrics dimensions with the Metaflow flow name.
#
# It's possible to set custom dimensions per metric, but in order to do this this, the append_dimensions parameter for
# each metric type must be set. The global append_dimensions config key doesn't support custom dimensions.
#
# An alternative to setting a custom dimension is to separate things using CloudWatch namespaces
# jq --arg flowname "${FLOW_NAME}" '.metrics.namespace = "MetaflowBatch/\($flowname)"' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > temp.json
#
# See: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html
#      ( CloudWatch agent configuration file: Metrics section)
jq --arg flowname "${FLOW_NAME}" '.metrics.metrics_collected |= map_values(.append_dimensions.FlowName |= $flowname)' /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json > temp.json

mv temp.json /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

nohup /opt/aws/amazon-cloudwatch-agent/bin/start-amazon-cloudwatch-agent -config /metaflow/amazon-cloudwatch-agent.json &
CLOUDWATCH_AGENT_PID=$!

CLOUDWATCH_LOG_FILE="/opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log"
LOG_MESSAGE="cloudwatch: publish with ForceFlushInterval"

check_log_file_contains_message() {
    [[ -f "$CLOUDWATCH_LOG_FILE" && $(grep -c "$LOG_MESSAGE" "$CLOUDWATCH_LOG_FILE") -gt 0 ]]
}

# Wait until the CW agent begins publishing metrics
until check_log_file_contains_message; do
    echo "Waiting for CloudWatch agent to publish metrics..."
    sleep 60
done

# CMD is handled by metaflow, see: https://outerbounds.com/docs/build-custom-image/#using-entrypoint-and-cmd
su - metaflow
"$@"
CMD_EXIT_CODE=$?

# Stop the CloudWatch Agent gracefully
kill $CLOUDWATCH_AGENT_PID
wait $CLOUDWATCH_AGENT_PID

# Exit with the exit code of the Metaflow commands
exit "$CMD_EXIT_CODE"
