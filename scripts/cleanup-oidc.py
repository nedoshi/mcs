import boto3
import json
from botocore.exceptions import ClientError

# --- Configuration ---
TARGET_USER = "target-iam-username"  # Username to target for deletion
DRY_RUN = True  # Set to False to actually execute deletions

def get_all_oidc_providers():
    """Fetches all existing OIDC providers in the account."""
    iam = boto3.client('iam')
    try:
        response = iam.list_open_id_connect_providers()
        providers = [p['Arn'] for p in response.get('OpenIDConnectProviders', [])]
        print(f"Total OIDC providers found in IAM: {len(providers)}")
        return providers
    except ClientError as e:
        print(f"Error listing OIDC providers: {e}")
        return []

def find_creator_via_cloudtrail(provider_arn):
    """Searches CloudTrail to identify who created a specific OIDC provider ARN."""
    cloudtrail = boto3.client('cloudtrail')
    try:
        # Lookup events specifically associated with this provider ARN resource string
        paginator = cloudtrail.get_paginator('lookup_events')
        page_iterator = paginator.paginate(
            LookupAttributes=[
                {
                    'AttributeKey': 'ResourceName',
                    'AttributeValue': provider_arn
                }
            ]
        )
        
        for page in page_iterator:
            for event in page['Events']:
                if event.get('EventName') == 'CreateOpenIDConnectProvider':
                    return event.get('Username'), event.get('EventTime')
                    
    except ClientError as e:
        print(f"Error querying CloudTrail for {provider_arn}: {e}")
    
    return None, None

def delete_provider(provider_arn):
    """Deletes the specified OIDC provider."""
    iam = boto3.client('iam')
    try:
        if DRY_RUN:
            print(f"[DRY RUN] Would delete provider: {provider_arn}")
        else:
            print(f"Deleting provider: {provider_arn}...")
            iam.delete_open_id_connect_provider(OpenIDConnectProviderArn=provider_arn)
            print("Successfully deleted.")
    except ClientError as e:
        print(f"Failed to delete {provider_arn}: {e}")

if __name__ == "__main__":
    providers = get_all_oidc_providers()
    matched_count = 0
    unknown_count = 0
    
    print("\nAuditing providers against CloudTrail logs...")
    for arn in providers:
        creator, created_at = find_creator_via_cloudtrail(arn)
        
        if creator:
            print(f"Provider: {arn} -> Created by: {creator} ({created_at})")
            if creator == TARGET_USER:
                matched_count += 1
                delete_provider(arn)
        else:
            # Occurs if the provider was created >90 days ago (outside default CloudTrail history)
            unknown_count += 1
            print(f"Provider: {arn} -> Creator: UNKNOWN (Older than 90 days)")
            
    print(f"\nAudit complete. Found {matched_count} providers created by '{TARGET_USER}'.")
    if unknown_count > 0:
        print(f"⚠️ {unknown_count} providers could not be identified because their creation events are older than 90 days.")

