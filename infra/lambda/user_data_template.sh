#!/bin/bash
################################################################################
# EC2のAmazon Linux実行時、user_dataとして、このシェルスクリプトを登録
# lambda_function.pyがこのファイルをテンプレートとして読み込み、
# 中括弧間はプレースホルダーとして指定値に変換されて、シェルスクリプトが生成されます。
# そのため、本来のシェルスクリプトとして使用する中括弧は、中括弧を二重に記述します。 
# このシェル出力は、CloudWatch Agentにより、CloudWatchに出力されます。
#
# Last updated: 2026-09-22 13:55:23
#   2026-09-22: exec の分解を read に変更（1語のとき実行シェル名が入力扱いになる不具合。BUG-007）、
#               run.conf の timeout（秒）で run.sh の実行時間を制限（超過時は FAILED 通知）
#
MY_NAME=${{0##*/}}

################################################################################
#set -eux # -e: exit on error, -u: exit on unset var, -x: print commands
set -eu # -e: exit on error, -u: exit on unset var

################################################################################
# 標準出力、標準エラー出力を、/var/log/cloud-init-output.log、loggerに出力します
# exec > >(tee /var/log/cloud-init-output.log|logger -t user-data -s 2>/dev/console) 2>&1

################################################################################
# vmの簡易的な性能表示
echo $MY_NAME
set -x
hostname
grep -c ^processor /proc/cpuinfo
free -h
lsblk -d -o NAME,ROTA,SIZE,MODEL
df -h
curl http://169.254.169.254/latest/meta-data/
set +x

################################################################################
echo "Start UserData Script  ---"

################################################################################
# --- CloudWatch Agentのセットアップ ---
echo "Setting up CloudWatch Agent..."
yum install -y amazon-cloudwatch-agent

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
CW_AGENT_CONFIG_PATH="/opt/aws/amazon-cloudwatch-agent/bin/config.json"
LOG_GROUP_NAME="{T_PRJ_PREFIX}-log-ec2-010"

# CloudWatch Agent設定ファイルを作成
cat <<EOF > $CW_AGENT_CONFIG_PATH
{{
  "agent": {{
    "run_as_user": "root"
  }},
  "logs": {{
    "logs_collected": {{
      "files": {{
        "collect_list": [
          {{
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "$LOG_GROUP_NAME",
            "log_stream_name": "$INSTANCE_ID",
            "timezone": "UTC"
          }}
        ]
      }}
    }}
  }}
}}
EOF

# CloudWatch Agentを起動
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:$CW_AGENT_CONFIG_PATH -s
echo "CloudWatch Agent setup complete."

################################################################################
# --- 設定をシェル変数に格納 T_はテンプレートとのやり取り ---
echo "Loading configuration..."
EXEC_COMMAND="{T_EXEC_COMMAND}"
BUCKET_NAME="{T_BUCKET_NAME}"
OUTPUT_BUCKET="{T_OUTPUT_BUCKET}"
LOG_FILE="{T_LOG_FILE}"
RESULT_FILE="{T_RESULT_FILE}"
MAIL_TO="{T_MAIL_TO}"
SMS_TO="{T_SMS_TO}"
SES_FROM="{T_SES_FROM}"
AWS_REGION="{T_AWS_REGION}" # EC2インスタンスのリージョンを取得します
TIMEOUT="{T_TIMEOUT}"       # run.sh の実行時間の上限（秒）。超えたら打ち切って FAILED 通知する

# --- 実行コマンドをパース ---
echo "Parsing execution command...EXEC_COMMAND: $EXEC_COMMAND"
# 先頭の語を実行シェル、残りを入力ファイルとする（1語のときは INPUT_FILES が空になる）
read -r EXEC_SCRIPT INPUT_FILES <<< "$EXEC_COMMAND"
echo "Parsing execution command...EXEC_SCRIPT: $EXEC_SCRIPT INPUT_FILES: $INPUT_FILES"

cd /home/ec2-user/ || {{ echo "ERROR: Failed to change directory to /home/ec2-user/"; exit 1; }}

# --- 実行スクリプトをダウンロード ---
echo "Downloading execution script: $EXEC_SCRIPT"
aws s3 cp "s3://$BUCKET_NAME/$EXEC_SCRIPT" ./ || {{ echo "FATAL: Failed to download execution script '$EXEC_SCRIPT' from bucket '$BUCKET_NAME'."; exit 1; }}

# --- 入力ファイルをダウンロード ---
if [ -n "$INPUT_FILES" ]; then
    for f in $INPUT_FILES;
    do
        echo "Downloading input file(s) matching pattern: $f"
        aws s3 cp "s3://$BUCKET_NAME/" ./ --recursive --exclude "*" --include "$f" || {{ echo "WARNING: Failed to download or no files found for pattern: $f"; }}
    done
else
    echo "No input files specified to download."
fi

################################################################################
# --- スクリプト実行 ---
chmod +x "$EXEC_SCRIPT" || {{ echo "ERROR: Failed to set execute permission on $EXEC_SCRIPT"; exit 1; }}


START_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "Executing command: ./$EXEC_COMMAND at $START_DATE"

set +e
CMD="./$EXEC_SCRIPT $INPUT_FILES"
echo "Running command as ec2-user: $CMD"
echo "Timeout: ${{TIMEOUT}} sec"
# --kill-after: TERM で終わらない場合は 60 秒後に KILL する
timeout --kill-after=60 "$TIMEOUT" su - ec2-user -c "$CMD" > "$LOG_FILE" 2>&1
EXEC_EXIT_CODE=$?
set -e

END_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "Execution finished with exit code: $EXEC_EXIT_CODE at $END_DATE"

################################################################################
# --- 成果物をアップロード ---
echo "Uploading log file: $LOG_FILE"
aws s3 cp "$LOG_FILE" "s3://$OUTPUT_BUCKET/" || {{ echo "ERROR: Failed to upload log file $LOG_FILE"; }}

for RESULT in $RESULT_FILE; do
    echo "Uploading result file: $RESULT"
    aws s3 cp "$RESULT" "s3://$OUTPUT_BUCKET/" || {{ echo "ERROR: Failed to upload result file $RESULT"; }}
done

################################################################################
# --- 実行結果を通知 ---
echo "Sending notification..."

if [ $EXEC_EXIT_CODE -eq 0 ]; then
    SUBJECT="SUCCESS: Job '$EXEC_SCRIPT' executed successfully"
    MESSAGE="Job '$EXEC_SCRIPT' completed successfully. $START_DATE - $END_DATE\n\nLog file: s3://$OUTPUT_BUCKET/$LOG_FILE\nResult file: s3://$OUTPUT_BUCKET/$RESULT_FILE"
elif [ $EXEC_EXIT_CODE -eq 124 ]; then
    SUBJECT="FAILED: Job '$EXEC_SCRIPT' timed out after $TIMEOUT sec"
    MESSAGE="Job '$EXEC_SCRIPT' was stopped by timeout ($TIMEOUT sec). $START_DATE - $END_DATE\n\nCheck the log file for details: s3://$OUTPUT_BUCKET/$LOG_FILE"
else
    SUBJECT="FAILED: Job '$EXEC_SCRIPT' failed with exit code $EXEC_EXIT_CODE"
    MESSAGE="Job '$EXEC_SCRIPT' failed with exit code $EXEC_EXIT_CODE. $START_DATE - $END_DATE\\n\nCheck the log file for details: s3://$OUTPUT_BUCKET/$LOG_FILE"
fi

################################################################################
# SMS通知
echo "SMS: $SMS_TO"
if [ -n "$SMS_TO" ]; then
    aws sns publish \
      --phone-number "$SMS_TO" \
      --message "$SUBJECT" \
      --region "$AWS_REGION" \
    || {{ echo "ERROR: Failed to send SMS notification"; }}
fi

################################################################################
# Email通知
echo "Email: $MAIL_TO"
if [ -n "$MAIL_TO" ] && [ -n "$SES_FROM" ]; then
    MESSAGE_BODY=$(cat <<EOM
{{
  "Subject": {{
    "Data": "$SUBJECT",
    "Charset": "UTF-8"
  }},
  "Body": {{
    "Text": {{
      "Data": "$MESSAGE",
      "Charset": "UTF-8"
    }}
  }}
}}
EOM
)
    DESTINATION_JSON=$(printf '{{"ToAddresses": ["%s"]}}' "$MAIL_TO")
    aws ses send-email --from "$SES_FROM" --destination "$DESTINATION_JSON" --message "$MESSAGE_BODY" --region "$AWS_REGION" || {{ echo "ERROR: Failed to send Email notification"; }}
fi

################################################################################
echo "--- All tasks finished. Terminating instance. ---"
sleep 30 # CloudWatch Agentがログを送信するのを待ちます
shutdown -h now
