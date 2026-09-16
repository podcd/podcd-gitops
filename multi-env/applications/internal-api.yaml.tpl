# internal-api is the private, iso-zone-only counterpart of edge-api.

apiVersion: v1
kind: Pod
metadata:
  name: internal-api
spec:
  restartPolicy: Always
  containers:
    - name: internal-api
      image: '{{ required "internalApi.image.repository is required" .Values.internalApi.image.repository }}:{{ required "internalApi.image.tag is required" .Values.internalApi.image.tag }}'
      env:
        - name: LOG_LEVEL
          value: '{{ default "info" .Values.logLevel }}'
      resources:
        limits:
          memory: '{{ default "128Mi" .Values.resources.memory }}'
