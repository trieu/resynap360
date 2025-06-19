#!/bin/bash
export $(cat .local_env | xargs)
uvicorn main:leobot --port 9999 --reload 