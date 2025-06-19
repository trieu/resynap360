# main.py

from fastapi import FastAPI, HTTPException, Query
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, PlainTextResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates

from redis import Redis
from pathlib import Path
import json
import time

from mangum import Mangum
from google import genai
from google.genai import types

import os
from dotenv import load_dotenv

from chatbot_models import Message

# Load environment variables
LOCAL_ENV_FILE = "./f6_omni_chatbot/.local_env"
if os.path.exists(LOCAL_ENV_FILE):
    load_dotenv(dotenv_path=LOCAL_ENV_FILE, override=True)
else:
    print(f"⚠️ Warning: {LOCAL_ENV_FILE} not found. Skipping local environment loading.")
    
    
VERSION = "1.0.0"
SERVICE_NAME = "LEO BOT VERSION:" + VERSION

LEOBOT_DEV_MODE = os.getenv("LEOBOT_DEV_MODE") == "true"
HOSTNAME = os.getenv("HOSTNAME")
REDIS_USER_SESSION_HOST = os.getenv("REDIS_USER_SESSION_HOST")
REDIS_USER_SESSION_PORT = os.getenv("REDIS_USER_SESSION_PORT")
REDIS_USER_SESSION_DB = os.getenv("REDIS_USER_SESSION_DB")
GOOGLE_GENAI_API_KEY = os.getenv("GOOGLE_GENAI_API_KEY")


TEMPERATURE_SCORE = 0.86

print("HOSTNAME " + HOSTNAME)
print("LEOBOT_DEV_MODE " + str(LEOBOT_DEV_MODE))

# Redis Client to get User Session
REDIS_CLIENT = Redis(host=REDIS_USER_SESSION_HOST,  port=REDIS_USER_SESSION_PORT, db=REDIS_USER_SESSION_DB, decode_responses=True)

FOLDER_RESOURCES = os.path.dirname(os.path.abspath(__file__)) + "/resources/"
FOLDER_TEMPLATES = FOLDER_RESOURCES + "templates"

def is_running_in_aws_lambda() -> bool:
    """
    Checks if the code is running in the AWS Lambda environment.

    Returns:
        True if running in Lambda, False otherwise.
    """
    # AWS sets this environment variable in the Lambda execution environment.
    return "AWS_LAMBDA_FUNCTION_NAME" in os.environ

# init FAST API leobot
leobot = FastAPI()
origins = ["*"]
leobot.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
leobot.mount("/resources", StaticFiles(directory=FOLDER_RESOURCES), name="resources")
templates = Jinja2Templates(directory=FOLDER_TEMPLATES)

def is_visitor_ready(visitor_id:str):
    return REDIS_CLIENT.hget(visitor_id, 'chatbot') == "leobot" or LEOBOT_DEV_MODE

##### API handlers #####


@leobot.get("/is-ready", response_class=JSONResponse)
@leobot.post("/is-ready", response_class=JSONResponse)
async def is_leobot_ready():
    isReady = isinstance(GOOGLE_GENAI_API_KEY, str)
    return {"ok": isReady}


@leobot.get("/", response_class=HTMLResponse)
async def root(request: Request):
    ts = int(time.time())
    data = {"request": request, "HOSTNAME": HOSTNAME, "LEOBOT_DEV_MODE": LEOBOT_DEV_MODE, 'timestamp': ts}
    return templates.TemplateResponse("chatbot.html", data)


@leobot.get("/get-visitor-info", response_class=JSONResponse)
async def get_visitor_info(visitor_id: str):
    isReady = isinstance(GOOGLE_GENAI_API_KEY, str)
    if not isReady:        
        return {"answer": "GOOGLE_GENAI_API_KEY is empty", "error_code": 501}
    if len(visitor_id) == 0: 
        return {"answer": "visitor_id is empty ", "error": True, "error_code": 500}
    profile_id = REDIS_CLIENT.hget(visitor_id, 'profile_id')
    if profile_id is None or len(profile_id) == 0: 
        if LEOBOT_DEV_MODE : 
            return {"answer": "local_dev", "error_code": 0}
        else:
            return {"answer": "Not found any profile in CDP", "error": True, "error_code": 404}
    name = str(REDIS_CLIENT.hget(visitor_id, 'name'))
    return {"answer": name, "error_code": 0}


@leobot.get("/ask", response_class=PlainTextResponse)
@leobot.post("/ask", response_class=JSONResponse)
async def ask(msg: Message):
    visitor_id = msg.visitor_id
    if len(visitor_id) == 0: 
        return {"answer": "visitor_id is empty ", "error": True, "error_code": 500}
    
    if LEOBOT_DEV_MODE:
        profile_id = "0"
    else:
        profile_id = REDIS_CLIENT.hget(visitor_id, 'profile_id')
        if profile_id is None or len(profile_id) == 0: 
            return {"answer": "Not found any profile in CDP", "error": True, "error_code": 404}
    
    leobot_ready = is_visitor_ready(visitor_id)
    question = msg.question
    prompt = msg.prompt
    lang_of_question = msg.answer_in_language
    context = msg.context
       
    if len(question) > 1000 or len(prompt) > 1000 :
        return {"answer": "Question must be less than 1000 characters!", "error": True, "error_code": 510}

    print("context: "+context)
    print("question: "+question)
    print("prompt: "+prompt)
    print("visitor_id: " + visitor_id)
    print("profile_id: "+profile_id)

    if leobot_ready:            
        # translate if need
        answer = ask_question(question=msg.question, context=msg.context)
        print("answer " + answer)
        data = {"question": question, "answer": answer, "visitor_id": visitor_id, "error_code": 0}
    else:
        data = {"answer": "Your profile is banned due to Violation of Terms", "error": True, "error_code": 666}
    return data
    
    
# The main function to ask LEO
# For security and portability, it is highly recommended to configure the API key
# once when the application starts, using environment variables.

def ask_question(question: str = 'Hi', context: str = '', temperature_score: float = TEMPERATURE_SCORE) -> str:
    """
    Asks a question to the LEO chatbot using the genai.Client pattern.

    Args:
        question: The question to ask.
        context: Additional context for the question.
        temperature_score: The temperature for the generation.

    Returns:
        The answer from the chatbot.
    """
    prompt_text = f"""<s> [INST] Your name is LEO and you are the AI chatbot.
                        The response should answer for the question and context:
                        {question}. {context} [/INST] </s>"""

    try:
        # Only run this block for Gemini Developer API
        client = genai.Client(api_key=GOOGLE_GENAI_API_KEY)
        
        # answer the question and context
        response = client.models.generate_content(
            model='gemini-2.0-flash-001',
            contents=prompt_text,
            config=types.GenerateContentConfig(
                safety_settings=[
                    types.SafetySetting(
                        category='HARM_CATEGORY_HATE_SPEECH',
                        threshold='BLOCK_ONLY_HIGH',
                    )
                ],
                temperature=temperature_score
            )
        )

        # Extract the text directly from the response, as shown in the example.
        if response and hasattr(response, 'text'):
            return response.text.strip()
        else:
            # Handle cases where the response might be blocked
            if response and response.prompt_feedback:
                 return f"The response was blocked. Reason: {response.prompt_feedback.block_reason.name}"
            return "No answer was returned from Gemini."

    except Exception as error:
        print(f"An exception occurred: {error}")
        return (
            "That's an interesting question. I have no answer now, but you can "
            f"<a target='_blank' href='https://www.google.com/search?q={question}'>search it on Google</a>."
        )
    

if is_running_in_aws_lambda():
    print("✅ This code is running inside an AWS Lambda function.")
    # AWS Lambda handler
    handler = Mangum(leobot)
else: 
    print("❌ This code is running in a local or non-Lambda environment.")
    # Example usage:
    
    # Ensure your API key is configured before calling the function.
    # genai.configure(api_key="YOUR_GOOGLE_API_KEY")
    answer = ask_question(question="What is the capital of Vietnam?", context="You are chatbot in Vietnam, please answer in Vietnamese")
    print(answer)
