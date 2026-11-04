FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir paho-mqtt==2.1.0 pillow
COPY notify.py lpr_experiment.py /app/
WORKDIR /app
CMD ["python3", "-u", "notify.py"]
