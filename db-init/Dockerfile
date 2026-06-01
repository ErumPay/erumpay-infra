FROM mysql:8.0

WORKDIR /db-init

COPY mysql/init/ ./sql/
COPY db-init/run-init.sh ./run-init.sh

RUN sed -i 's/\r$//' ./run-init.sh && chmod +x ./run-init.sh

ENTRYPOINT ["./run-init.sh"]
