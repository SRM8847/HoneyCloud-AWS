#!/bin/bash
yum update -y
yum install -y python3 python3-pip

pip3 install flask boto3

cat > /opt/imds_mock.py << 'PYEOF'
${flask_app}
PYEOF

cat > /etc/systemd/system/imds_mock.service << 'SVCEOF'
[Unit]
Description=HoneyCloud IMDS Mock
After=network.target

[Service]
ExecStart=/usr/bin/python3 /opt/imds_mock.py
Restart=always
Environment=AWS_REGION=${aws_region}

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable imds_mock
systemctl start imds_mock
