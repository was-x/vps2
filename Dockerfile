FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata

ARG NGROK_AUTHTOKEN="34914Ptd48gbHXPmcNYxWEXCxpu_3V4itphQ1buQFCVEn8C1h"
ARG ROOT_PASSWORD="Darkboy336"

# Install everything in one layer to minimize issues
RUN apt-get update && \
    apt-get install -y \
      curl \
      wget \
      openssh-server \
      sudo \
      nano \
      git \
      software-properties-common \
      python3 \
      python3-pip \
      python3-venv \
      python3-distutils \
    && add-apt-repository ppa:deadsnakes/ppa -y \
    && apt-get update \
    && apt-get install -y python3.12 python3.12-venv \
    && ln -fs /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo "root:${ROOT_PASSWORD}" | chpasswd \
    && mkdir -p /var/run/sshd \
    && mkdir -p /root/.ssh \
    && ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" \
    && cp /root/.ssh/id_rsa /root/ssh-key.pem \
    && chmod 600 /root/ssh-key.pem \
    && cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys \
    && chmod 600 /root/.ssh/authorized_keys \
    && echo "PermitRootLogin yes" >> /etc/ssh/sshd_config \
    && echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config \
    && echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config \
    && echo "ListenAddress 0.0.0.0" >> /etc/ssh/sshd_config \
    && curl -sSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null \
    && echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | tee /etc/apt/sources.list.d/ngrok.list \
    && apt-get update \
    && apt-get install -y ngrok \
    && ngrok config add-authtoken "${NGROK_AUTHTOKEN}" \
    && echo "Dark" > /etc/hostname \
    && echo 'export PS1="root@Dark:\\w# "' >> /root/.bashrc \
    && rm -rf /var/lib/apt/lists/*

# Install Flask using system Python 3 (not Python 3.12) to avoid distutils issues
RUN python3 -m pip install flask

# Create a simple web server script
RUN echo 'from flask import Flask, send_file, jsonify\nimport subprocess\nimport json\n\napp = Flask(__name__)\n\n@app.route("/")\ndef home():\n    return """\n    <!DOCTYPE html>\n    <html>\n    <head>\n        <title>SSH Server with Ngrok</title>\n        <style>\n            body { font-family: Arial, sans-serif; margin: 40px; }\n            .container { max-width: 800px; margin: 0 auto; }\n            .card { background: #f5f5f5; padding: 20px; margin: 10px 0; border-radius: 5px; }\n            .btn { display: inline-block; padding: 10px 20px; background: #007bff; color: white; text-decoration: none; border-radius: 5px; }\n            pre { background: #333; color: #fff; padding: 15px; border-radius: 5px; overflow-x: auto; }\n        </style>\n    </head>\n    <body>\n        <div class="container">\n            <h1>🚀 SSH Server with Ngrok Tunnel</h1>\n            \n            <div class="card">\n                <h2>📄 Download SSH Key</h2>\n                <p>Download your private key for SSH access:</p>\n                <a href="/download-pem" class="btn">Download PEM File</a>\n            </div>\n\n            <div class="card">\n                <h2>🔗 Connection Info</h2>\n                <p><strong>Host:</strong> Check ngrok status below</p>\n                <p><strong>Port:</strong> Check ngrok status below</p>\n                <p><strong>Username:</strong> root</p>\n                <p><strong>Authentication:</strong> Use the downloaded PEM file</p>\n            </div>\n\n            <div class="card">\n                <h2>🔌 SSH Command</h2>\n                <pre id="ssh-command">ssh -i ssh-key.pem root@HOST -p PORT</pre>\n            </div>\n\n            <div class="card">\n                <h2>📊 Ngrok Status</h2>\n                <pre id="ngrok-status">Loading ngrok status...</pre>\n            </div>\n\n            <div class="card">\n                <h2>🔄 Health Check</h2>\n                <p>Service status: <span style="color: green;">✅ Active</span></p>\n                <p>SSH Server: <span style="color: green;">✅ Running on 0.0.0.0:22</span></p>\n                <p>Web Server: <span style="color: green;">✅ Running on 0.0.0.0:5000</span></p>\n            </div>\n        </div>\n\n        <script>\n            fetch("/ngrok-status")\n                .then(response => response.json())\n                .then(data => {\n                    if (data.tunnels && data.tunnels.length > 0) {\n                        const tunnel = data.tunnels[0];\n                        document.getElementById("ngrok-status").textContent = JSON.stringify(data, null, 2);\n                        \n                        const url = new URL(tunnel.public_url);\n                        const host = url.hostname;\n                        const port = url.port;\n                        document.getElementById("ssh-command").textContent = \n                            `ssh -i ssh-key.pem root@${host} -p ${port}`;\n                    }\n                })\n                .catch(error => {\n                    document.getElementById("ngrok-status").textContent = \n                        "Error fetching ngrok status: " + error.message;\n                });\n        </script>\n    </body>\n    </html>\n    """\n\n@app.route("/download-pem")\ndef download_pem():\n    return send_file("/root/ssh-key.pem", \n                     as_attachment=True, \n                     download_name="ssh-key.pem",\n                     mimetype="application/x-pem-file")\n\n@app.route("/ngrok-status")\ndef ngrok_status():\n    try:\n        result = subprocess.run(["curl", "-s", "http://localhost:4040/api/tunnels"], \n                              capture_output=True, text=True, timeout=5)\n        if result.returncode == 0:\n            return jsonify(json.loads(result.stdout))\n        else:\n            return jsonify({"error": "Unable to fetch ngrok status"})\n    except Exception as e:\n        return jsonify({"error": str(e)})\n\n@app.route("/health")\ndef health():\n    return "OK"\n\nif __name__ == "__main__":\n    app.run(host="0.0.0.0", port=5000)' > /app.py

# Create startup script
RUN echo '#!/bin/bash\n\
echo "=== Starting SSH Server === "\n\
/usr/sbin/sshd -D &\n\
\n\
echo "=== Starting Web Server === "\n\
python3 /app.py &\n\
\n\
echo "=== Starting Ngrok Tunnel === "\n\
sleep 5\n\
ngrok tcp 22 --log=stdout' > /start.sh

RUN chmod +x /start.sh

EXPOSE 22 5000

CMD ["/start.sh"]
