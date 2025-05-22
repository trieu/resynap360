#!/bin/bash

# Name of the final zip file
ZIP_NAME="f2_event_to_entities.zip"

echo '📦 Building $ZIP_NAME'

# Step into the dependencies directory and zip contents
# pip freeze > requirements.txt

# Install dependencies
rm -r dependencies
pip install --upgrade -t dependencies -r requirements.txt
sleep 1
cd dependencies || { echo "❌ dependencies/ folder not found!"; exit 1; }

rm $ZIP_NAME
echo "🔄 Zipping dependencies..."
zip -r9 ../$ZIP_NAME . > /dev/null

# Step back to project root
cd ..

# Add main.py and processor.py
echo "➕ Adding main.py, db_utils.py and processor.py to the zip..."
zip -g $ZIP_NAME main.py > /dev/null
zip -g $ZIP_NAME db_utils.py > /dev/null

# Add processor.py for domain data processing
zip -g $ZIP_NAME processor.py > /dev/null

echo "✅ Package built: $ZIP_NAME"
