FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements-pipecat.txt ./
RUN pip install --no-cache-dir -r requirements-pipecat.txt

COPY pipecat_agent.py ./

EXPOSE 8000

CMD ["sh", "-c", "uvicorn pipecat_agent:app --host 0.0.0.0 --port ${PORT:-8000}"]
