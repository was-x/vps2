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

# Install common utilities, SSH, and software-properties-common
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
    && rm -rf /var/lib/apt/lists/*

# Python 3.12
RUN add-apt-repository ppa:deadsnakes/ppa -y && \
    apt-get update && \
    apt-get install -y --no-install-recommends python3.12 python3.12-venv && \
    rm -rf /var/lib/apt/lists/*

# Make python3 point to python3.12
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1

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

# Create web server to serve PEM file and status
RUN echo 'from flask import Flask, send_file, render_template_string\nimport os\nimport subprocess\n\napp = Flask(__name__)\n\n@app.route("/")\ndef home():\n    try:\n        # Get ngrok status\n        result = subprocess.run(["curl", "-s", "http://localhost:4040/api/tunnels"], \n                              capture_output=True, text=True)\n        ngrok_status = result.stdout if result.returncode == 0 else "Unable to fetch ngrok status"\n        \n        html = """\n        <!DOCTYPE html>\n        <html>\n        <head>\n            <title>SSH Server with Ngrok</title>\n            <style>\n                body { font-family: Arial, sans-serif; margin: 40px; }\n                .container { max-width: 800px; margin: 0 auto; }\n                .card { background: #f5f5f5; padding: 20px; margin: 10px 0; border-radius: 5px; }\n                .btn { display: inline-block; padding: 10px 20px; background: #007bff; color: white; text-decoration: none; border-radius: 5px; }\n                pre { background: #333; color: #fff; padding: 15px; border-radius: 5px; overflow-x: auto; }\n            </style>\n        </head>\n        <body>\n            <div class="container">\n                <h1>🚀 SSH Server with Ngrok Tunnel</h1>\n                \n                <div class="card">\n                    <h2>📄 Download SSH Key</h2>\n                    <p>Download your private key for SSH access:</p>\n                    <a href="/download-pem" class="btn">Download PEM File</a>\n                </div>\n\n                <div class="card">\n                    <h2>🔗 Connection Info</h2>\n                    <p><strong>Host:</strong> 2.tcp.us-cal-1.ngrok.io (check ngrok status below for actual host)</p>\n                    <p><strong>Port:</strong> 12822 (check ngrok status below for actual port)</p>\n                    <p><strong>Username:</strong> root</p>\n                    <p><strong>Authentication:</strong> Use the downloaded PEM file</p>\n                </div>\n\n                <div class="card">\n                    <h2>🔌 SSH Command</h2>\n                    <pre>ssh -i ssh-key.pem root@2.tcp.us-cal-1.ngrok.io -p 12822</pre>\n                </div>\n\n                <div class="card">\n                    <h2>📊 Ngrok Status</h2>\n                    <pre>{{ ngrok_status }}</pre>\n                </div>\n            </div>\n        </body>\n        </html>\n        """\n        return render_template_string(html, ngrok_status=ngrok_status)\n    except Exception as e:\n        return f"Error: {str(e)}"\n\n@app.route("/download-pem")\ndef download_pem():\n    return send_file("/root/ssh-key.pem", \n                     as_attachment=True, \n                     download_name="ssh-key.pem",\n                     mimetype="application/x-pem-file")\n\n@app.route("/health")\ndef health():\n    return "OK"\n\nif __name__ == "__main__":\n    app.run(host="0.0.0.0", port=5000)' > /app.py

EXPOSE 22 5000

# Start all services
CMD ["sh", "-c", "/usr/sbin/sshd -D & python3 /app.py & ngrok tcp 22 --log=stdout"]
