# 이미지 하나로 두 서비스를 실행한다: 기본은 API, compose의 ui 서비스가 명령을 streamlit으로 바꾼다.
FROM python:3.13-slim

# 로그를 버퍼 없이 바로 출력하고(.pyc는 만들지 않음), Streamlit은 첫 실행 질문 없이 서버로 뜬다.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    STREAMLIT_SERVER_HEADLESS=true

WORKDIR /app

# 의존성 먼저: requirements.txt가 그대로면 코드만 고쳐도 이 레이어(가장 느린 단계)는 캐시를 쓴다.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY *.py .

# root가 아닌 사용자로 실행한다. data/는 volume이 붙을 자리이며, 이 사용자가 쓸 수 있어야 한다.
RUN useradd --create-home app && mkdir -p data && chown app:app data
USER app

EXPOSE 8000 8501
# 0.0.0.0: 컨테이너 밖(포트 매핑, 다른 컨테이너)에서 들어올 수 있게 모든 인터페이스에서 받는다.
CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8000"]
