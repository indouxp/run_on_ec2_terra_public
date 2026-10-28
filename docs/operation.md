# オペレーション手順
<!-- Last updated: 2026-09-22 18:02:41（です・ます調に統一、無関係なディレクトリの表示を削除） -->

## 概要
run_on_ec2_terra でのオペレーション手順を、2026-09-22 の実際の操作と出力で示します。作業ディレクトリは `work/`（`.gitignore` 済み）です。

## YYYYmmdd.tar.gz作成
run.conf に記載する run.sh への引数となる圧縮ファイルを作成します。

```bash
$ ts-pigz.sh 20260913.tar.gz 20260913*MOV
ts-pigz.sh: tar -cf - 20260913_175441.MOV 20260913_180015.MOV 20260913_180144.MOV 20260913_180336.MOV 20260913_180555.MOV 20260913_180814.MOV 20260913_181106.MOV 20260913_181532.MOV 20260913_181716.MOV 20260913_181907.MOV 20260913_182112.MOV 20260913_182329.MOV 20260913_182612.MOV 20260913_183035.MOV 20260913_183415.MOV | pigz -p 4 > 20260913.tar.gz 
ts-pigz.sh: 20260913.tar.gzに圧縮しました。
$

$ ls -l
合計 3266144
lrwxrwxrwx 1 user user         36  9月 22 08:02 20250901-run_on_ec2 -> /home/user/prjs/20250901-run_on_ec2/
-rw-rw-r-- 1 user user 3344465544  9月 22 11:31 20260913.tar.gz
drwxrwxr-x 2 user user       4096  9月 22 11:26 20260917.downloaded_files
drwxrwxr-x 2 user user       4096  9月 22 11:27 20260918.downloaded_files
-rwxrwxr-x 1 user user       5178  9月 22 09:14 aws-get-lastlog.sh
-rw-rw-r-- 1 user user      23696  9月 22 08:49 output.json
-rw-rw-r-- 1 user user        552  9月 22 11:10 run.conf
-rw-rw-r-- 1 user user        584  9月 22 08:13 run.conf.bak-20260922-085232
-rw-rw-r-- 1 user user        586  9月 22 08:03 run.conf.org
-rw-rw-r-- 1 user user        586  9月 22 08:03 run.conf.skl
-rw-rw-r-- 1 user user        922  9月 22 08:58 upl-run.sh.log
$ 
```

## run.confの編集
YYYYmmdd.tar.gz を含め、実行のための定義ファイルを更新します。"exec" は毎回変更が必要です。

```bash
$ vi run.conf
$ cat run.conf
{
  "exec": "run.sh 20260913.tar.gz",
  "log": "run.log",
  "result": "*.mp4 *act.log",
  "mail": "宛先メール",
  "sms": "+81スマホ電話番号",
  "ec2_role_name": "ts-030-role-ec2-010",
  "subnet_name": "ts-030-subnet-010",
  "sg_name": "ts-030-sg-010",
  "ec2_instance_name_tag": "ts-030-ec2-010",
  "output_bucket": "ts-030-bkt-out",
  "sns_topic_name": "ts-030-sns-010",
  "default_ami_id": "ami-09ed31f8f34719e20",
  "instance_type": "c6i.4xlarge",
  "ses_from_email": "FROMヘッダーに記載されるメールアドレス",
  "prj_prefix": "ts-030",
  "ebs_size": 50
}
$ 
```
## S3へのアップロード
upl-run.sh を実行すると、run.conf に記載した YYYYmmdd.tar.gz、run.sh、run.conf の順に S3 バケットへアップロードされます。

```bash
$ ../tool/upl-run.sh 
2026-09-22 11:33:17 pc01 68778 upl-run.sh: START
2026-09-22 11:33:19 pc01 68778 upl-run.sh: identity: arn:aws:sts::123456789012:assumed-role/ts-030-role-operate/botocore-session-0000000002
2026-09-22 11:33:19 pc01 68778 upl-run.sh: config: ./run.conf / instance_type: c6i.4xlarge / exec: run.sh 20260913.tar.gz
定義ファイルのアップロードで EC2（c6i.4xlarge）が起動します。続行しますか [y/N]: y
2026-09-22 11:33:21 pc01 68778 upl-run.sh: upload: 20260913.tar.gz (3.2G)
2026-09-22 11:33:52 pc01 68778 upl-run.sh: upload: /home/user/work/run_on_ec2_terra/tool/run.sh (12K)
2026-09-22 11:33:54 pc01 68778 upl-run.sh: upload: ./run.conf (4.0K)
2026-09-22 11:33:55 pc01 68778 upl-run.sh: upload complete. Lambda should now launch the EC2 instance.
2026-09-22 11:33:55 pc01 68778 upl-run.sh: END RC=0
$
```

ログを確認します。
```bash
$ cat upl-run.sh.log 
2026-09-22 08:55:46 identity: arn:aws:sts::123456789012:assumed-role/ts-030-role-operate/botocore-session-0000000001
2026-09-22 08:55:46 config: ./run.conf / instance_type: c6i.4xlarge / exec: run.sh 20260917.tar.gz
定義ファイルのアップロードで EC2（c6i.4xlarge）が起動します。続行しますか [y/N]: 2026-09-22 08:55:52 upload: 20260917.tar.gz (4.4G)
2026-09-22 08:57:21 identity: arn:aws:sts::123456789012:assumed-role/ts-030-role-operate/botocore-session-0000000001
2026-09-22 08:57:21 config: ./run.conf / instance_type: c6i.4xlarge / exec: run.sh 20260917.tar.gz
定義ファイルのアップロードで EC2（c6i.4xlarge）が起動します。続行しますか [y/N]: 2026-09-22 08:57:25 upload: 20260917.tar.gz (4.4G)
2026-09-22 08:58:07 upload: run.sh (8.0K)
2026-09-22 08:58:09 upload: ./run.conf (4.0K)
2026-09-22 08:58:11 upload complete. Lambda should now launch the EC2 instance.
$ 
```

## 現在状況の確認
get-now.sh で現在の状況を確認します。処理が終わるとメールが送られます。

```bash
 ../tool/get-now.sh 
2026-09-22 11:34:10 pc01 69005 get-now.sh: START
2026-09-22 11:34:10 pc01 69005 get-now.sh: ===== [1] identity =====
  ts-030-role-operate: arn:aws:sts::123456789012:assumed-role/ts-030-role-operate/botocore-session-0000000002
  ts-usr-readonly: arn:aws:iam::123456789012:user/ts-usr-readonly
2026-09-22 11:34:13 pc01 69005 get-now.sh: ===== [2] EC2 (tag Project=ts-030) =====
  i-0123456789abcdef1  terminated  c6i.4xlarge  launch=2026-09-22T02:11:10+00:00  reason=User initiated
  i-0123456789abcdef0  running  c6i.4xlarge  launch=2026-09-22T02:33:59+00:00  reason=
2026-09-22 11:34:15 pc01 69005 get-now.sh: ===== [3] s3://ts-030-bkt-in =====
  objects=3 total_bytes=3344475315
  2026-09-22T02:33:24+00:00  3344465544 20260913.tar.gz
  2026-09-22T02:33:56+00:00  552        run.conf
  2026-09-22T02:33:54+00:00  9219       run.sh
2026-09-22 11:34:16 pc01 69005 get-now.sh: ===== [3] s3://ts-030-bkt-out =====
  (empty)
2026-09-22 11:34:18 pc01 69005 get-now.sh: ===== [4/5] /aws/lambda/ts-030-lmd-010 (last 20 events) =====
  stream: 2026/09/22/[$LATEST]d1ba953c099b4603bf7af41a23a9ac3d
  2026-09-22 11:33:57  [INFO]   2026-09-22T02:33:57.285Z                Found credentials in environment variables.
  2026-09-22 11:33:57  START RequestId: 2aed0c63-a69b-426e-b812-03713cd4eb83 Version: $LATEST
  2026-09-22 11:33:57  [INFO]   2026-09-22T02:33:57.625Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Triggered by S3 event='{'s3SchemaVersion': '1.0', 'configurationId': 'tf-s3-lambda-20260921162616592600000004', 'bucket': {'name': 'ts-030-bkt-in', 'ownerIdentity': {'principalId': 'AEXAMPLEOWNER0'}, 'arn': 'arn:aws:s3:::ts-030-bkt-in'}, 'object': {'key': 'run.conf', 'size': 552, 'eTag': '381f471bcb951ddc27dd8d92dbb2fa17', 'sequencer': '006AB1E9138D7D537E'}}: bucket='ts-030-bkt-in', key='run.conf'
  2026-09-22 11:33:57  [INFO]   2026-09-22T02:33:57.805Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Loaded config: {'exec': 'run.sh 20260913.tar.gz', 'log': 'run.log', 'result': '*.mp4 *act.log', 'mail': 'user@example.com', 'sms': '+819012345678', 'ec2_role_name': 'ts-030-role-ec2-010', 'subnet_name': 'ts-030-subnet-010', 'sg_name': 'ts-030-sg-010', 'ec2_instance_name_tag': 'ts-030-ec2-010', 'output_bucket': 'ts-030-bkt-out', 'sns_topic_name': 'ts-030-sns-010', 'default_ami_id': 'ami-09ed31f8f34719e20', 'instance_type': 'c6i.4xlarge', 'ses_from_email': 'sender@example.com', 'prj_prefix': 'ts-030', 'ebs_size': 50}
  2026-09-22 11:33:57  [INFO]   2026-09-22T02:33:57.805Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Starting configuration validation.
  2026-09-22 11:33:57  [INFO]   2026-09-22T02:33:57.805Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Configuration validation successful.
  2026-09-22 11:33:57  [INFO]   2026-09-22T02:33:57.805Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Checking for running instances with tag: ts-030-ec2-010
  2026-09-22 11:33:58  [INFO]   2026-09-22T02:33:58.023Z        2aed0c63-a69b-426e-b812-03713cd4eb83    No running or pending instances found with name tag: ts-030-ec2-010
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.003Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Found resource IDs: {'subnet_id': 'subnet-0123456789abcdef1', 'sg_id': 'sg-0123456789abcdef0', 'instance_profile_arn': 'arn:aws:iam::123456789012:instance-profile/ts-030-role-ec2-010'}
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    config['exec']=run.sh 20260913.tar.gz
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    bucket_name=ts-030-bkt-in
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    config.get('log')=run.log
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    result=*.mp4 *act.log
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    config['mail']=user@example.com
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    config['sms']=+819012345678
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    ses_from_email=sender@example.com
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    ec2_client.meta.region_name=ap-northeast-1
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Launching EC2 instance with params: {'ImageId': 'ami-09ed31f8f34719e20', 'InstanceType': 'c6i.4xlarge', 'IamInstanceProfile': {'Arn': 'arn:aws:iam::123456789012:instance-profile/ts-030-role-ec2-010'}, 'NetworkInterfaces': [{'DeviceIndex': 0, 'SubnetId': 'subnet-0123456789abcdef1', 'Groups': ['sg-0123456789abcdef0'], 'AssociatePublicIpAddress': True}], 'TagSpecifications': [{'ResourceType': 'instance', 'Tags': [{'Key': 'Name', 'Value': 'ts-030-ec2-010'}, {'Key': 'Project', 'Value': 'ts-030'}, {'Key': 'autogen-by', 'Value': 'ts-030-system'}]}, {'ResourceType': 'volume', 'Tags': [{'Key': 'Name', 'Value': 'ts-030-ec2-010'}, {'Key': 'Project', 'Value': 'ts-030'}, {'Key': 'autogen-by', 'Value': 'ts-030-system'}]}], 'MinCount': 1, 'MaxCount': 1, 'InstanceInitiatedShutdownBehavior': 'terminate', 'BlockDeviceMappings': [{'DeviceName': '/dev/xvda', 'Ebs': {'DeleteOnTermination': True, 'VolumeSize': 50}}]}
  2026-09-22 11:34:00  [INFO]   2026-09-22T02:34:00.143Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Successfully initiated launch of EC2 instance: i-0123456789abcdef0
  2026-09-22 11:34:00  [INFO]   2026-09-22T02:34:00.148Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Waiting for instance i-0123456789abcdef0 to enter 'running' state...
2026-09-22 11:34:21 pc01 69005 get-now.sh: ===== [4/5] ts-030-log-ec2-010 (last 20 events) =====
  stream: i-0123456789abcdef1
  2026-09-22 11:22:58  Uploading result file: 20260918_184035.mp4
upload: ./20260918_184035.mp4 to s3://ts-030-bkt-out/20260918_184035.mp4ile(s) remaining
  2026-09-22 11:22:59  Uploading result file: 20260918_184320.mp4
upload: ./20260918_184320.mp4 to s3://ts-030-bkt-out/20260918_184320.mp4ile(s) remaining
  2026-09-22 11:22:59  Uploading result file: 20260918_184911.mp4
upload: ./20260918_184911.mp4 to s3://ts-030-bkt-out/20260918_184911.mp4ile(s) remaining
  2026-09-22 11:23:00  Uploading result file: 20260918_185058.mp4
upload: ./20260918_185058.mp4 to s3://ts-030-bkt-out/20260918_185058.mp4ile(s) remaining
  2026-09-22 11:23:01  Uploading result file: 20260918_185232.mp4
upload: ./20260918_185232.mp4 to s3://ts-030-bkt-out/20260918_185232.mp4ile(s) remaining
  2026-09-22 11:23:01  Uploading result file: simple-act.log
upload: ./simple-act.log to s3://ts-030-bkt-out/simple-act.log    ith 1 file(s) remaining
  2026-09-22 11:23:01  Sending notification...
  2026-09-22 11:23:02  SMS: +819012345678
  2026-09-22 11:23:02  {
    "MessageId": "1b4cd267-ddab-5d61-893f-b14c356dbaac"
  2026-09-22 11:23:02  }
  2026-09-22 11:23:02  Email: user@example.com
  2026-09-22 11:23:02  {
    "MessageId": "010601a0c6ec7cf7-a404a0ab-971c-4a80-ac7a-d35c964b8d26-000000"
  2026-09-22 11:23:02  }
  2026-09-22 11:23:07  --- All tasks finished. Terminating instance. ---
2026-09-22 11:34:23 pc01 69005 get-now.sh: items failed: 0
2026-09-22 11:34:23 pc01 69005 get-now.sh: END RC=0
$
```
メール送信後、EC2 インスタンスは shutdown し、自己 terminate で削除されます。

```bash
$ ../tool/get-now.sh 
2026-09-22 12:09:00 pc01 76566 get-now.sh: START
2026-09-22 12:09:00 pc01 76566 get-now.sh: ===== [1] identity =====
  ts-030-role-operate: arn:aws:sts::123456789012:assumed-role/ts-030-role-operate/botocore-session-0000000003
  ts-usr-readonly: arn:aws:iam::123456789012:user/ts-usr-readonly
2026-09-22 12:09:04 pc01 76566 get-now.sh: ===== [2] EC2 (tag Project=ts-030) =====
  i-0123456789abcdef1  terminated  c6i.4xlarge  launch=2026-09-22T02:11:10+00:00  reason=User initiated
  i-0123456789abcdef0  terminated  c6i.4xlarge  launch=2026-09-22T02:33:59+00:00  reason=User initiated
2026-09-22 12:09:07 pc01 76566 get-now.sh: ===== [3] s3://ts-030-bkt-in =====
  (empty)
2026-09-22 12:09:09 pc01 76566 get-now.sh: ===== [3] s3://ts-030-bkt-out =====
  (empty)
2026-09-22 12:09:11 pc01 76566 get-now.sh: ===== [4/5] /aws/lambda/ts-030-lmd-010 (last 20 events) =====
  stream: 2026/09/22/[$LATEST]d1ba953c099b4603bf7af41a23a9ac3d
  2026-09-22 11:33:57  [INFO]   2026-09-22T02:33:57.805Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Loaded config: {'exec': 'run.sh 20260913.tar.gz', 'log': 'run.log', 'result': '*.mp4 *act.log', 'mail': 'user@example.com', 'sms': '+819012345678', 'ec2_role_name': 'ts-030-role-ec2-010', 'subnet_name': 'ts-030-subnet-010', 'sg_name': 'ts-030-sg-010', 'ec2_instance_name_tag': 'ts-030-ec2-010', 'output_bucket': 'ts-030-bkt-out', 'sns_topic_name': 'ts-030-sns-010', 'default_ami_id': 'ami-09ed31f8f34719e20', 'instance_type': 'c6i.4xlarge', 'ses_from_email': 'sender@example.com', 'prj_prefix': 'ts-030', 'ebs_size': 50}
  2026-09-22 11:33:57  [INFO]   2026-09-22T02:33:57.805Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Starting configuration validation.
  2026-09-22 11:33:57  [INFO]   2026-09-22T02:33:57.805Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Configuration validation successful.
  2026-09-22 11:33:57  [INFO]   2026-09-22T02:33:57.805Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Checking for running instances with tag: ts-030-ec2-010
  2026-09-22 11:33:58  [INFO]   2026-09-22T02:33:58.023Z        2aed0c63-a69b-426e-b812-03713cd4eb83    No running or pending instances found with name tag: ts-030-ec2-010
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.003Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Found resource IDs: {'subnet_id': 'subnet-0123456789abcdef1', 'sg_id': 'sg-0123456789abcdef0', 'instance_profile_arn': 'arn:aws:iam::123456789012:instance-profile/ts-030-role-ec2-010'}
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    config['exec']=run.sh 20260913.tar.gz
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    bucket_name=ts-030-bkt-in
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    config.get('log')=run.log
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    result=*.mp4 *act.log
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    config['mail']=user@example.com
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    config['sms']=+819012345678
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    ses_from_email=sender@example.com
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    ec2_client.meta.region_name=ap-northeast-1
  2026-09-22 11:33:59  [INFO]   2026-09-22T02:33:59.004Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Launching EC2 instance with params: {'ImageId': 'ami-09ed31f8f34719e20', 'InstanceType': 'c6i.4xlarge', 'IamInstanceProfile': {'Arn': 'arn:aws:iam::123456789012:instance-profile/ts-030-role-ec2-010'}, 'NetworkInterfaces': [{'DeviceIndex': 0, 'SubnetId': 'subnet-0123456789abcdef1', 'Groups': ['sg-0123456789abcdef0'], 'AssociatePublicIpAddress': True}], 'TagSpecifications': [{'ResourceType': 'instance', 'Tags': [{'Key': 'Name', 'Value': 'ts-030-ec2-010'}, {'Key': 'Project', 'Value': 'ts-030'}, {'Key': 'autogen-by', 'Value': 'ts-030-system'}]}, {'ResourceType': 'volume', 'Tags': [{'Key': 'Name', 'Value': 'ts-030-ec2-010'}, {'Key': 'Project', 'Value': 'ts-030'}, {'Key': 'autogen-by', 'Value': 'ts-030-system'}]}], 'MinCount': 1, 'MaxCount': 1, 'InstanceInitiatedShutdownBehavior': 'terminate', 'BlockDeviceMappings': [{'DeviceName': '/dev/xvda', 'Ebs': {'DeleteOnTermination': True, 'VolumeSize': 50}}]}
  2026-09-22 11:34:00  [INFO]   2026-09-22T02:34:00.143Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Successfully initiated launch of EC2 instance: i-0123456789abcdef0
  2026-09-22 11:34:00  [INFO]   2026-09-22T02:34:00.148Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Waiting for instance i-0123456789abcdef0 to enter 'running' state...
  2026-09-22 11:34:15  [INFO]   2026-09-22T02:34:15.552Z        2aed0c63-a69b-426e-b812-03713cd4eb83    Instance i-0123456789abcdef0 is now running.
  2026-09-22 11:34:15  END RequestId: 2aed0c63-a69b-426e-b812-03713cd4eb83
  2026-09-22 11:34:15  REPORT RequestId: 2aed0c63-a69b-426e-b812-03713cd4eb83   Duration: 17929.00 ms   Billed Duration: 18608 ms       Memory Size: 256 MB        Max Memory Used: 121 MB Init Duration: 678.89 ms
2026-09-22 12:09:14 pc01 76566 get-now.sh: ===== [4/5] ts-030-log-ec2-010 (last 20 events) =====
  stream: i-0123456789abcdef0
  2026-09-22 11:44:52  Uploading result file: 20260913_182112.mp4
upload: ./20260913_182112.mp4 to s3://ts-030-bkt-out/20260913_182112.mp4ile(s) remaining
  2026-09-22 11:44:52  Uploading result file: 20260913_182329.mp4
upload: ./20260913_182329.mp4 to s3://ts-030-bkt-out/20260913_182329.mp4ile(s) remaining
  2026-09-22 11:44:53  Uploading result file: 20260913_182612.mp4
upload: ./20260913_182612.mp4 to s3://ts-030-bkt-out/20260913_182612.mp4ile(s) remaining
  2026-09-22 11:44:54  Uploading result file: 20260913_183035.mp4
upload: ./20260913_183035.mp4 to s3://ts-030-bkt-out/20260913_183035.mp4ile(s) remaining
  2026-09-22 11:44:55  Uploading result file: 20260913_183415.mp4
upload: ./20260913_183415.mp4 to s3://ts-030-bkt-out/20260913_183415.mp4ile(s) remaining
  2026-09-22 11:44:55  Uploading result file: simple-act.log
upload: ./simple-act.log to s3://ts-030-bkt-out/simple-act.log    ith 1 file(s) remaining
  2026-09-22 11:44:56  Sending notification...
  2026-09-22 11:44:56  SMS: +819012345678
  2026-09-22 11:44:56  {
    "MessageId": "853223da-7c05-5c6b-844f-40f191ede559"
  2026-09-22 11:44:56  }
  2026-09-22 11:44:56  Email: user@example.com
  2026-09-22 11:44:56  {
    "MessageId": "010601a0c7008a71-623f4e57-f3cb-4dc9-b3bc-30e16b69f0fe-000000"
  2026-09-22 11:44:56  }
  2026-09-22 11:45:01  --- All tasks finished. Terminating instance. ---
2026-09-22 12:09:17 pc01 76566 get-now.sh: items failed: 0
2026-09-22 12:09:17 pc01 76566 get-now.sh: END RC=0
0 [0.01s] 260922-120917 user@pc01:~/work/run_on_ec2_terra/work:
$ 
```

## バケットからファイルをダウンロード

EC2 が動作中の場合は、エラー終了します。

```bash
$ ../tool/pop-s3.sh 
2026-09-22 11:45:28 pc01 72839 pop-s3.sh: START
2026-09-22 11:45:29 pc01 72839 pop-s3.sh: identity: arn:aws:sts::123456789012:assumed-role/ts-030-role-operate/botocore-session-0000000002
2026-09-22 11:45:31 pc01 72839 pop-s3.sh: ERROR: ts-030-ec2-010 is still active (1). wait until it terminates
2026-09-22 11:45:31 pc01 72839 pop-s3.sh: END RC=1
$ 
```

EC2 の終了後にダウンロードします。

```bash
$ ../tool/pop-s3.sh 
2026-09-22 11:46:05 pc01 73051 pop-s3.sh: START
2026-09-22 11:46:06 pc01 73051 pop-s3.sh: identity: arn:aws:sts::123456789012:assumed-role/ts-030-role-operate/botocore-session-0000000002
2026-09-22 11:46:10 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_175441.mp4 (105393051 bytes) -> ./downloaded_files/20260913_175441.mp4
2026-09-22 11:46:14 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_180015.mp4 (42906438 bytes) -> ./downloaded_files/20260913_180015.mp4
2026-09-22 11:46:18 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_180144.mp4 (31662084 bytes) -> ./downloaded_files/20260913_180144.mp4
2026-09-22 11:46:22 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_180336.mp4 (44330107 bytes) -> ./downloaded_files/20260913_180336.mp4
2026-09-22 11:46:26 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_180555.mp4 (40473991 bytes) -> ./downloaded_files/20260913_180555.mp4
2026-09-22 11:46:30 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_180814.mp4 (34500875 bytes) -> ./downloaded_files/20260913_180814.mp4
2026-09-22 11:46:34 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_181106.mp4 (46975858 bytes) -> ./downloaded_files/20260913_181106.mp4
2026-09-22 11:46:38 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_181532.mp4 (24079212 bytes) -> ./downloaded_files/20260913_181532.mp4
2026-09-22 11:46:42 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_181716.mp4 (38295534 bytes) -> ./downloaded_files/20260913_181716.mp4
2026-09-22 11:46:46 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_181907.mp4 (24091105 bytes) -> ./downloaded_files/20260913_181907.mp4
2026-09-22 11:46:49 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_182112.mp4 (37485931 bytes) -> ./downloaded_files/20260913_182112.mp4
2026-09-22 11:46:53 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_182329.mp4 (21224013 bytes) -> ./downloaded_files/20260913_182329.mp4
2026-09-22 11:46:57 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_182612.mp4 (74446425 bytes) -> ./downloaded_files/20260913_182612.mp4
2026-09-22 11:47:02 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_183035.mp4 (22491496 bytes) -> ./downloaded_files/20260913_183035.mp4
2026-09-22 11:47:06 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/20260913_183415.mp4 (19091614 bytes) -> ./downloaded_files/20260913_183415.mp4
2026-09-22 11:47:09 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/run.log (191672 bytes) -> ./downloaded_files/run.log
2026-09-22 11:47:12 pc01 73051 pop-s3.sh: download: s3://ts-030-bkt-out/simple-act.log (213122 bytes) -> ./downloaded_files/simple-act.log
2026-09-22 11:47:15 pc01 73051 pop-s3.sh: result: total 17, ok 17, ng 0 (saved to ./downloaded_files)
2026-09-22 11:47:15 pc01 73051 pop-s3.sh: END RC=0
$
```

## バケット内のファイルを削除

処理終了後、S3 バケット内のファイルを削除します。必ず pop-s3.sh のあとに実行してください。

```bash
$ ../tool/del-s3.sh 
2026-09-22 12:08:42 pc01 76384 del-s3.sh: START
2026-09-22 12:08:44 pc01 76384 del-s3.sh: identity: arn:aws:sts::123456789012:assumed-role/ts-030-role-operate/botocore-session-0000000003
  20260913.tar.gz       3344465544
  run.conf      552
  run.sh        9219
2026-09-22 12:08:47 pc01 76384 del-s3.sh: target: s3://ts-030-bkt-in 3 objects, 3344475315 bytes
s3://ts-030-bkt-in の 3 件を削除します（取り消せません）。続行しますか [y/N]: y
2026-09-22 12:08:52 pc01 76384 del-s3.sh: deleted: s3://ts-030-bkt-in/20260913.tar.gz
2026-09-22 12:08:54 pc01 76384 del-s3.sh: deleted: s3://ts-030-bkt-in/run.conf
2026-09-22 12:08:56 pc01 76384 del-s3.sh: deleted: s3://ts-030-bkt-in/run.sh
2026-09-22 12:08:56 pc01 76384 del-s3.sh: result: total 3, deleted 3, ng 0
2026-09-22 12:08:56 pc01 76384 del-s3.sh: END RC=0
$ 
```



