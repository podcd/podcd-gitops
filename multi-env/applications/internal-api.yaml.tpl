# internal-api is the private, iso-zone-only counterpart of edge-api.

apiVersion: gitops.podcd.io/v1
kind: Application
metadata:
  name: internal-api
spec:
  image: '{{ required "internalApi.image.repository is required" .Values.internalApi.image.repository }}:{{ required "internalApi.image.tag is required" .Values.internalApi.image.tag }}'
  env:
    LOG_LEVEL: '{{ default "info" .Values.logLevel }}'
  resources:
    memory: '{{ default "128M" .Values.resources.memory }}'
