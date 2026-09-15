# edge-api is the public-facing application for the dmz zone.

apiVersion: gitops.podcd.io/v1
kind: Application
metadata:
  name: edge-api
spec:
  image: '{{ required "edgeApi.image.repository is required" .Values.edgeApi.image.repository }}:{{ required "edgeApi.image.tag is required" .Values.edgeApi.image.tag }}'
  env:
    LOG_LEVEL: '{{ default "info" .Values.logLevel }}'
    PUBLIC_HOSTNAME: '{{ default "" .Values.publicHostname }}'
  resources:
    memory: '{{ default "256M" .Values.resources.memory }}'
    cpu: '{{ default "100%" .Values.resources.cpu }}'
