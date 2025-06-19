#!/bin/bash

# Name of the final zip file
ZIP_NAME="aws-lambda-artifact.zip"



echo "📦 Building AWS Lambda deployment package..."

# Step into the dependencies directory and zip contents
pip freeze > requirements.txt
pip install --upgrade -t dependencies -r requirements.txt
sleep 1
cd dependencies || { echo "❌ dependencies/ folder not found!"; exit 1; }

rm $ZIP_NAME
echo "🔄 Zipping dependencies..."
zip -r9 ../$ZIP_NAME . > /dev/null

# Step back to project root
cd ..

# Add main.py and optionally .local_env
echo "➕ Adding main.py to the zip..."
zip -g $ZIP_NAME main.py > /dev/null

echo "✅ Package built: $ZIP_NAME"