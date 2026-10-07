# sagemaker_endpoint_async_metrics

Two asynchronous inference endpoints sharing one model and one endpoint
configuration: `busy` is invoked when recording and `idle` never is.

An endpoint is async when its configuration carries an
`AsyncInferenceConfig`. It queues requests, reads each one from S3 rather than
from the call, and writes the response back to S3, so the bucket holds the
model, a request (`request.csv`) and the responses. An async endpoint publishes
none of the real-time invocation metrics, such as `Invocations`, only the
async ones, such as `InvocationsProcessed`.

This is a fixture of its own rather than more endpoints in
`sagemaker_endpoint_metrics`, because recording against that fixture renames
every endpoint in it, and with them every recording made against it.

`model.tar.gz` is a copy of the one in `../sagemaker_endpoint_metrics`, whose
README says how it's built.

Neither endpoint has a GPU, so the GPU metrics aren't recorded for async
endpoints.

`../sagemaker_endpoint_metrics/probe_metrics.py` finds these endpoints by
their name prefix, so applying this module and running the probe checks the
async sections of `c7n/data/sagemaker_metrics.yaml`.
