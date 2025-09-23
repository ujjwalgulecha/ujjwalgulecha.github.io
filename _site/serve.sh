#!/bin/bash

# Kill any existing Jekyll processes on port 4000
echo "Checking for existing Jekyll processes..."
if lsof -ti:4000 > /dev/null 2>&1; then
    echo "Killing existing processes on port 4000..."
    lsof -ti:4000 | xargs kill -9
    sleep 2
fi

# Set up environment
export PATH="$PATH:/Users/ujjwalgulecha/.gem/ruby/2.6.0/bin"

echo "Starting Jekyll server..."
bundle exec jekyll serve --host 0.0.0.0 --port 4000 --livereload