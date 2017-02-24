FROM python:3.6-alpine
MAINTAINER https://github.com/muccg

ENV VIRTUAL_ENV /env
ENV PIP_NO_CACHE_DIR="off"
ENV PYTHON_PIP_VERSION 9.0.1
ENV PYTHONIOENCODING=UTF-8

ENV PROJECT_NAME docker-django-sql-explorer
ENV PROJECT_SOURCE https://github.com/muccg/docker-django-sql-explorer.git
ENV PRODUCTION 1
ENV DEBUG 0
ENV STATIC_ROOT /data/static
ENV WRITABLE_DIRECTORY /data/scratch
ENV MEDIA_ROOT /data/static/media
ENV LOG_DIRECTORY /data/log
ENV DJANGO_SETTINGS_MODULE sqlexplorer.settings

RUN apk --no-cache add \
    bash \
    build-base \
    ca-certificates \
    groff \
    jpeg-dev \
    less \
    linux-headers \
    mailcap \
    mariadb-dev \
    pcre-dev \
    postgresql-dev \
    zlib-dev

RUN python3.6 -m venv $VIRTUAL_ENV \
    && $VIRTUAL_ENV/bin/pip install --upgrade \
    pip==$PYTHON_PIP_VERSION

ENV PATH $VIRTUAL_ENV/bin:$PATH

COPY docker-entrypoint.sh /docker-entrypoint.sh

COPY requirements.txt /app/requirements.txt
RUN $VIRTUAL_ENV/bin/pip install --upgrade -r /app/requirements.txt

RUN addgroup -g 1000 python \
  && adduser -D -h /data -H -S -u 1000 -G python python \
  && mkdir /data \
  && chown python:python /data

RUN mkdir -p /app && chown python:python /app
COPY . /app
RUN $VIRTUAL_ENV/bin/pip install -e /app/sqlexplorer

USER python
ENV HOME /data
WORKDIR /data

EXPOSE 9100 9101
VOLUME ["/data"]

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["uwsgi"]
