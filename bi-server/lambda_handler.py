"""
AWS Lambda handler — deploy this to make the API accessible from Salesforce in production.
Package with requirements.txt and deploy via AWS Console or CLI.
Environment variables required: REDSHIFT_HOST, REDSHIFT_USER, REDSHIFT_PASSWORD,
REDSHIFT_DATABASE, REDSHIFT_PORT
"""
import json
from api_server import app
from mangum import Mangum

handler = Mangum(app)
