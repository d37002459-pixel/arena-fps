FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx gettext-base ca-certificates curl unzip libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*

ARG GODOT_VERSION=4.4.1-stable
RUN curl -fsSL -o /tmp/godot.zip https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip \
 && unzip /tmp/godot.zip -d /tmp \
 && mv /tmp/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
 && rm /tmp/godot.zip

WORKDIR /app
COPY . /app
RUN godot --headless --path /app --import || true

ENV PORT=10000
EXPOSE 10000
CMD ["/app/server/start.sh"]
