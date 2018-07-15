version: '2.3'

volumes:
  data-psql:
    driver: local

networks:
  net-opennms:
    driver: bridge

services:

  database:
    image: postgres:10
    hostname: database
    mem_limit: 512m
    mem_swappiness: 0
    environment:
      - TZ=Europe/Berlin
      - POSTGRES_HOST=database
      - POSTGRES_PORT=5432
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
    volumes:
      - data-psql:/var/lib/postgresql/data
    networks:
      - net-opennms
    healthcheck:
      test: ["CMD-SHELL", "pg_isready", "-U", "postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
    ports:
      - "5432"

  horizon:
    image: opennms/build-env:latest
    hostname: horizon
    init: true
    mem_limit: 2g
    mem_swappiness: 0
    cap_add:
      - NET_ADMIN
    environment:
      - TZ=Europe/Berlin
      - JAVA_OPTS=-XX:+UseParallelGC -XX:+PrintFlagsFinal -XX:+UnlockExperimentalVMOptions -XX:+UseCGroupMemoryLimitForHeap
      - OPENNMS_DBNAME=opennms
      - OPENNMS_DBUSER=opennms
      - OPENNMS_DBPASS=opennms
      - POSTGRES_HOST=database
      - POSTGRES_PORT=5432
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - OPENNMS_HOME=/opt/opennms
    networks:
      - net-opennms
    volumes:
      - ./opennms/target/INSTALL_VERSION:/opt/opennms
      - ./etc-overlay:/opt/opennms-etc-overlay
      - ./jetty-overlay:/opt/opennms-jetty-webinf-overlay
    command: ["/docker-entrypoint.sh", "-s"]
    depends_on:
      database:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "-I", "http://localhost:8980/opennms/login.jsp"]
      interval: 1m
      timeout: 5s
      retries: 3
    ports:
      - "8980"
      - "8101"
      - "61616"
      - "6343/udp"

