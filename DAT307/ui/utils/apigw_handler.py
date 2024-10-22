import streamlit as st
from dotenv import load_dotenv
import os
import requests

load_dotenv()
APIGWURL=os.getenv('APIGWURL')
APIGWSTAGE = os.getenv('APIGWSTAGE')
AWS_REGION=os.getenv('AWS_REGION')
       

def get_incidents(incidentStatus):
    headers = {'Authorization': f"{st.session_state['token']}", 'Content-Type': 'application/json'}
    url = f'{APIGWURL}{APIGWSTAGE}/get-incidents'
    try:
       response = requests.get(url,params={"incidentStatus": incidentStatus}, headers = headers)
       response.raise_for_status()
       items = response.json()['Items']
       if len(items) == 0 :
           print("No incidents available")

       return response.json()['Items']
    except requests.exceptions.RequestException as e:
       print (f"Error in calling /alerts API: {e}")
       return None


def get_runbook(id, description):
    headers = {'Authorization': f"{st.session_state['token']}", 'Content-Type': 'application/json'}
    url = f'{APIGWURL}{APIGWSTAGE}/get-incident-runbook'
    try:
       response = requests.get(url, params={"query": description, "id": id}, headers = headers)
       response.raise_for_status()
       return response.json()
    except requests.exceptions.RequestException as e:
       print (f"Error in calling /alerts API: {e}")
       return None

def incident_remediate(id, description):
    print("Calling the agent to take action")
    headers = {'Authorization': f"{st.session_state['token']}", 'Content-Type': 'application/json'}
    url = f'{APIGWURL}{APIGWSTAGE}/post-incident-action'
    try:
       data = {'action':description, 'id': id}
       response = requests.post(url, headers = headers, json=data)
       response.raise_for_status()
       return response.json()
    except requests.exceptions.RequestException as e:
       print (f"Error in calling /alerts API: {e}")
       return None   
    
