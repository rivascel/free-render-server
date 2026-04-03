# Stage 1: Base image with expensive operations first
FROM alpine:latest AS base

# Build arguments for optional features
ARG INSTALL_N8N=false
ARG INSTALL_NGROK=true

# Install system dependencies (expensive but stable)
RUN apk update && apk add --no-cache \
    nginx \
    python3 \
    python3-dev \
    py3-pip \
    git \
    su-exec \
    shadow \
    bash \
    curl \
    unzip \
    openssh \
    jq \
    chromium \
    chromium-chromedriver \
    nodejs \
    npm

# Verify installations
RUN echo "Node.js version: $(node --version)" && \
    echo "npm version: $(npm --version)" && \
    echo "Python version: $(python3 --version)" && \
    echo "Pip version: $(pip3 --version)" && \
    echo "Git version: $(git --version)"

# Install n8n globally - only if enabled
RUN if [ "$INSTALL_N8N" = "true" ]; then \
        npm install -g n8n; \
        echo "n8n version: $(n8n --version)"; \
    else \
        echo "Skipping n8n installation (INSTALL_N8N=false)"; \
    fi

# Install ngrok - only if enabled
RUN if [ "$INSTALL_NGROK" = "true" ]; then \
        curl -sSL https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz \
        | tar xz -C /usr/local/bin; \
        echo "ngrok version: $(ngrok version)"; \
    else \
        echo "Skipping ngrok installation (INSTALL_NGROK=false)"; \
    fi

# Create node user for n8n (only if enabled)
RUN if [ "$INSTALL_N8N" = "true" ]; then \
        addgroup -g 1000 node && \
        adduser -u 1000 -G node -s /bin/sh -D node; \
        echo "Created node user for n8n"; \
    else \
        echo "Skipping node user creation (INSTALL_N8N=false)"; \
    fi

# Configure SSH
RUN ssh-keygen -A && \
    mkdir -p /var/run/sshd && \
    echo 'root:Secure@FreeRender2024' | chpasswd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Stage 2: Final image with configuration
FROM base

# Build arguments need to be redeclared in new stage
ARG INSTALL_N8N=false
ARG INSTALL_NGROK=true

# Create necessary directories
RUN mkdir -p /var/log/nginx \
    && mkdir -p /run/nginx \
    && mkdir -p /var/cache/nginx \
    && mkdir -p /var/www \
    && mkdir -p /app

# Create n8n directories only if n8n is enabled
RUN if [ "$INSTALL_N8N" = "true" ]; then \
        mkdir -p /home/node/.n8n; \
        echo "Created n8n directories"; \
    else \
        echo "Skipping n8n directory creation (INSTALL_N8N=false)"; \
    fi

# Clone and build AsambleasReact
WORKDIR /app
RUN git clone https://github.com/rivascel/AsambleasReact.git asambleas
WORKDIR /app/asambleas
RUN npm install && npm run build

# Copy configuration files (you need to create these)
# COPY nginx.conf /etc/nginx/nginx.conf
# COPY start_services.sh /start_services.sh
# RUN chmod +x /start_services.sh

# Fix permissions
RUN chown -R nginx:nginx /var/log/nginx /var/cache/nginx /run/nginx

# Fix n8n permissions only if n8n is enabled
RUN if [ "$INSTALL_N8N" = "true" ]; then \
        chown -R node:node /home/node; \
        echo "Set n8n permissions"; \
    else \
        echo "Skipping n8n permission setup (INSTALL_N8N=false)"; \
    fi

# Environment variables
ENV N8N_ENABLED=${INSTALL_N8N}
ENV N8N_HOST=0.0.0.0
ENV N8N_PORT=5678
ENV N8N_PROTOCOL=http
ENV N8N_PATH=/n8n/
ENV N8N_DIAGNOSTICS_ENABLED=false
ENV N8N_ANONYMOUS_USAGE=false

# Create Nginx configuration
RUN echo 'server { \
    listen 80; \
    server_name _; \
    \
    location /asambleas { \
        alias /app/asambleas/build; \
        try_files $uri $uri/ /index.html; \
        index index.html; \
    } \
    \
    location /n8n/ { \
        proxy_pass http://localhost:5678/; \
        proxy_http_version 1.1; \
        proxy_set_header Upgrade $http_upgrade; \
        proxy_set_header Connection "upgrade"; \
        proxy_set_header Host $host; \
        proxy_set_header X-Real-IP $remote_addr; \
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; \
        proxy_set_header X-Forwarded-Proto $scheme; \
    } \
    \
    location / { \
        return 200 "Server is running.\nAccess n8n at /n8n\nAccess Asambleas at /asambleas\n"; \
        add_header Content-Type text/plain; \
    } \
}' > /etc/nginx/http.d/default.conf

# Expose ports
EXPOSE 80 5678 22

# Start services
CMD if [ "$N8N_ENABLED" = "true" ]; then \
        n8n start & \
    fi; \
    nginx -g "daemon off;"
