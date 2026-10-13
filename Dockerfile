FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt   .
COPY app.py   .
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 5005
CMD ["python", "app.py"]