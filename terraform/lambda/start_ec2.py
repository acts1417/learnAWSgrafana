import boto3

def handler(event, context):
    ec2 = boto3.client('ec2', region_name='us-east-1')

    instances = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:auto-schedule', 'Values': ['true']},
            {'Name': 'instance-state-name', 'Values': ['stopped']}
        ]
    )

    instance_ids = [
        i['InstanceId']
        for r in instances['Reservations']
        for i in r['Instances']
    ]

    if instance_ids:
        ec2.start_instances(InstanceIds=instance_ids)
        print(f"Started instances: {instance_ids}")
    else:
        print("No stopped instances with auto-schedule=true found")
