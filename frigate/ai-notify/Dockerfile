FROM python:3.12-slim
RUN pip install --no-cache-dir paho-mqtt==2.1.0
COPY notify.py /app/notify.py
WORKDIR /app
CMD ["python3", "-u", "notify.py"]
