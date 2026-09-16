# edge-api is the public-facing application for the dmz zone.

apiVersion: v1
kind: Pod
metadata:
  name: edge-api
spec:
  restartPolicy: Always
  containers:
    - name: edge-api
      image: '{{ required "edgeApi.image.repository is required" .Values.edgeApi.image.repository }}:{{ required "edgeApi.image.tag is required" .Values.edgeApi.image.tag }}'
      env:
        - name: LOG_LEVEL
          value: '{{ default "info" .Values.logLevel }}'
        - name: PUBLIC_HOSTNAME
          value: '{{ default "" .Values.publicHostname }}'
      resources:
        limits:
          memory: '{{ default "256Mi" .Values.resources.memory }}'
          cpu: '{{ default "1" .Values.resources.cpu }}'
