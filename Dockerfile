FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata

ARG NGROK_AUTHTOKEN="34914Ptd48gbHXPmcNYxWEXCxpu_3V4itphQ1buQFCVEn8C1h"
ARG ROOT_PASSWORD="Darkboy336"

# Install minimal tools and tzdata
RUN apt-get update && \
    apt-get install -y --no-install-recommends apt-utils ca-certificates gnupg2 curl wget lsb-release tzdata && \
    ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime && \
    dpkg-reconfigure --frontend noninteractive tzdata && \
    rm -rf /var/lib/apt/lists/*

# Install common utilities, SSH, and Python with distutils
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      openssh-server \
      wget \
      curl \
      git \
      nano \
      sudo \
      software-properties-common \
      python3 \
      python3-pip \
      python3-distutils \
      python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Python 3.12 with full development packages
RUN add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      python3.12 \
      python3.12-venv \
      python3.12-distutils \
      python3.12-dev \
    && rm -rf /var/lib/apt/lists/*

# Make python3 point to python3.12 and ensure pip works
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3 get-pip.py && \
    rm get-pip.py

# Install Flask for web server
RUN pip3 install flask

# SSH Configuration - Force binding to 0.0.0.0
RUN echo "root:${ROOT_PASSWORD}" | chpasswd \
    && mkdir -p /var/run/sshd \
    && mkdir -p /root/.ssh \
    && chmod 700 /root/.ssh

# Generate SSH key pair for PEM file
RUN ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" \
    && cp /root/.ssh/id_rsa /root/ssh-key.pem \
    && chmod 600 /root/ssh-key.pem \
    && cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys \
    && chmod 600 /root/.ssh/authorized_keys

# Configure SSH to bind to all interfaces and allow key authentication
RUN echo "PermitRootLogin yes" >> /etc/ssh/sshd_config \
    && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config \
    && echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config \
    && echo "ListenAddress 0.0.0.0" >> /etc/ssh/sshd_config \
    && echo "Port 22" >> /etc/ssh/sshd_config

# ngrok official repo
RUN curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
    && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | tee /etc/apt/sources.list.d/ngrok.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends ngrok \
    && rm -rf /var/lib/apt/lists/*

# Add ngrok token
RUN if [ -n "${NGROK_AUTHTOKEN}" ]; then ngrok config add-authtoken "${NGROK_AUTHTOKEN}"; fi

# Optional hostname file
RUN echo "Dark" > /etc/hostname

# Force bash prompt
RUN echo 'export PS1="root@Dark:\\w# "' >> /root/.bashrc

# Create a simple web server to serve PEM file (using Python http.server instead of Flask)
RUN echo '#!/bin/bash\n\
# Simple status page\n\
cat > /status.html << EOF\n\
<!DOCTYPE html>\n\
<html>\n\
<head>\n\
    <title>SSH Server with Ngrok</title>\n\
    <style>\n\
        body { font-family: Arial, sans-serif; margin: 40px; }\n\
        .container { max-width: 800px; margin: 0 auto; }\n\
        .card { background: #f5f5f5; padding: 20px; margin: 10px 0; border-radius: 5px; }\n\
        .btn { display: inline-block; padding: 10px 20px; background: #007bff; color: white; text-decoration: none; border-radius: 5px; }\n\
        pre { background: #333; color: #fff; padding: 15px; border-radius: 5px; overflow-x: auto; }\n\
    </style>\n\
</head>\n\
<body>\n\
    <div class="container">\n\
        <h1>🚀 SSH Server with Ngrok Tunnel</h1>\n\
        \n\
        <div class="card">\n\
            <h2>📄 Download SSH Key</h2>\n\
            <p>Download your private key for SSH access:</p>\n\
            <a href="/ssh-key.pem" class="btn">Download PEM File</a>\n\
        </div>\n\
\n\
        <div class="card">\n\
            <h2>🔗 Connection Info</h2>\n\
            <p><strong>Host:</strong> Check ngrok status below</p>\n\
            <p><strong>Port:</strong> Check ngrok status below</p>\n\
            <p><strong>Username:</strong> root</p>\n\
            <p><strong>Authentication:</strong> Use the downloaded PEM file</p>\n\
        </div>\n\
\n\
        <div class="card">\n\
            <h2>🔌 SSH Command</h2>\n\
            <pre id="ssh-command">ssh -i ssh-key.pem root@HOST -p PORT</pre>\n\
        </div>\n\
\n\
        <div class="card">\n\
            <h2>📊 Ngrok Status</h2>\n\
            <pre id="ngrok-status">Loading ngrok status...</pre>\n\
        </div>\n\
\n\
        <div class="card">\n\
            <h2>🔄 Health Check</h2>\n\
            <p>Service status: <span style="color: green;">✅ Active</span></p>\n\
            <p>SSH Server: <span style="color: green;">✅ Running on 0.0.0.0:22</span></p>\n\
            <p>Web Server: <span style="color: green;">✅ Running on 0.0.0.0:5000</span></p>\n\
        </div>\n\
    </div>\n\
\n\
    <script>\n\
        // Fetch ngrok status\n\
        fetch(\"http://localhost:4040/api/tunnels\")\n\
            .then(response => response.json())\n\
            .then(data => {\n\
                if (data.tunnels && data.tunnels.length > 0) {\n\
                    const tunnel = data.tunnels[0];\n\
                    document.getElementById(\"ngrok-status\").textContent = JSON.stringify(data, null, 2);\n\
                    \n\
                    // Update SSH command with actual host and port\n\
                    const url = new URL(tunnel.public_url);\n\
                    const host = url.hostname;\n\
                    const port = url.port;\n\
                    document.getElementById(\"ssh-command\").textContent = \n\
                        `ssh -i ssh-key.pem root@${host} -p ${port}`;\n\
                }\n\
            })\n\
            .catch(error => {\n\
                document.getElementById(\"ngrok-status\").textContent = \n\
                    "Error fetching ngrok status: " + error.message;\n\
            });\n\
    </script>\n\
</body>\n\
</html>\n\
EOF\n\
\n\
# Start web server in background\n\
cd / && python3 -m http.server 5000 --bind 0.0.0.0 &\n\
\n\
# Start SSH\n/usr/sbin/sshd -D &\n\
\n\
# Start ngrok\necho "Starting ngrok..."\nngrok tcp 22 --log=stdout' > /start.sh

RUN chmod +x /start.sh

EXPOSE 22 5000

# Use the start script
CMD ["/start.sh"]
