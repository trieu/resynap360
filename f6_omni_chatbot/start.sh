#!/bin/bash
export $(cat .local_env | xargs)
uvicorn main:app --reload