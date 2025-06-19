#!/bin/bash

# Name of the final zip file for the Lambda layer
ZIP_NAME="aws-lambda-artifact.zip"

echo "📦 Building AWS Lambda deployment package..."

# Ensure we start from a clean slate
rm -f $ZIP_NAME
rm -rf dependencies/

# Create the dependencies directory
mkdir dependencies

# Step 1: Install production dependencies into the 'dependencies' folder
echo "⚙️ Installing dependencies..."
pip install --upgrade -t dependencies -r requirements.txt
sleep 1 # Give a moment for file system operations

# Step 2: Zip the installed dependencies first
echo "🔄 Zipping dependencies..."
cd dependencies || { echo "❌ 'dependencies/' folder not found! Exiting."; exit 1; }
zip -r9 ../$ZIP_NAME . > /dev/null
cd ..

# Step 3: Add all your Python source files from the root directory
echo "➕ Adding Python application files (*.py)..."
zip -g $ZIP_NAME *.py > /dev/null

# Step 4: Add the 'resources' folder and its contents
# The -r flag ensures it recursively includes all files and subdirectories
if [ -d "resources" ]; then
  echo "➕ Adding 'resources' folder..."
  zip -gr $ZIP_NAME resources > /dev/null
else
  echo "⚠️ Warning: 'resources' folder not found. Skipping."
fi

echo "✅ Package built successfully: $ZIP_NAME"