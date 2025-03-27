#!/bin/bash
set -e

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default user directories
USER_HOME="$HOME"
OUTPUT_DIR="$USER_HOME/models/llamafiles"
DOWNLOAD_DIR="$USER_HOME/models/huggingface"
CONFIG_FILE="$USER_HOME/.config/makelamafile/config"

# Default binary location (will be overridden by config if available)
# This fallback is for running outside of Homebrew
BIN_DIR="$SCRIPT_DIR/bin"

# Try to load config file if it exists
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

# Check if we're on macOS
if [ "$(uname)" != "Darwin" ]; then
  echo "Error: This version is only compatible with macOS"
  exit 1
fi

# Function to show usage information
show_usage() {
  echo "Usage: $0 [OPTIONS] GGUF_FILE_OR_URL"
  echo
  echo "Options:"
  echo "  -h, --help                 Show this help message"
  echo "  -o, --output-dir DIR       Set output directory (default: $OUTPUT_DIR)"
  echo "  -n, --name MODEL_NAME      Custom name for model (default: derived from filename)"
  echo "  -d, --description DESC     Custom description for the model"
  echo "  -t, --test                 Test the generated llamafile after creation"
  echo "  -p, --prompt PROMPT        Test prompt to use with the model (default: 'Tell me a short story')"
  echo
  echo "This script converts a GGUF model file to a llamafile executable and creates"
  echo "supporting documentation in markdown format."
}

# Function to download a file if URL is provided
download_file() {
  local url="$1"
  local output_file="${2:-$(basename "$url")}"
  
  # Remove ?download=true suffix if present
  url="${url%?download=true}"
  
  echo "Downloading $output_file from $url..."
  
  # Determine if we should download to the default download directory
  if [ "${output_file##*/}" = "${output_file}" ]; then
    # No path specified, use download dir
    mkdir -p "$DOWNLOAD_DIR"
    output_file="$DOWNLOAD_DIR/$(basename "$output_file")"
  fi
  
  curl -L -o "$output_file" "$url"
  
  echo "Download complete!"
  echo "$output_file"
}

# Function to calculate SHA256 hash
calculate_hash() {
  local file="$1"
  shasum -a 256 "$file" | cut -d ' ' -f 1
}

# Function to extract model information
extract_model_info() {
  local model_file="$1"
  
  # For TinyLLama, use hardcoded values
  if [[ "$model_file" == *"TinyLLama"* || "$model_file" == *"tinyllama"* ]]; then
    echo "1.1B:2048:LLaMA"
    return
  fi
  
  # For other models, try to extract info from filename but return Unknown if not possible
  if [[ "$model_file" == *"7b"* ]]; then
    echo "7B:4096:Unknown"
  elif [[ "$model_file" == *"13b"* ]]; then
    echo "13B:4096:Unknown"
  elif [[ "$model_file" == *"70b"* ]]; then
    echo "70B:4096:Unknown"
  else
    echo "Unknown:Unknown:Unknown"
  fi
}

# Function to generate a markdown documentation file
generate_docs() {
  local model_name="$1"
  local input_file="$2"
  local output_file="$3"
  local hash="$4"
  local description="${5:-A language model converted to llamafile format}"
  local model_info="$6"
  local doc_file="${output_dir}/${model_name}/README.md"
  
  # Parse model information
  local parameters=$(echo "$model_info" | cut -d: -f1)
  local context_size=$(echo "$model_info" | cut -d: -f2)
  local model_type=$(echo "$model_info" | cut -d: -f3)
  
  echo "Generating documentation in $doc_file..."
  
  mkdir -p "$(dirname "$doc_file")"
  
  # Create documentation
  cat > "$doc_file" << EOF
# ${model_name} llamafile

## Model Information

- **Original File**: \`$(basename "$input_file")\`
- **LLamafile**: \`$(basename "$output_file")\`
- **SHA256**: \`${hash}\`
- **Size**: $(du -h "$output_file" | cut -f1)
EOF

  # Add model parameters if known
  if [ "$parameters" != "Unknown" ]; then
    echo "- **Parameters**: ${parameters}" >> "$doc_file"
  fi
  
  # Add context size if known
  if [ "$context_size" != "Unknown" ]; then
    echo "- **Context Size**: ${context_size}" >> "$doc_file"
  fi
  
  # Add model type if known
  if [ "$model_type" != "Unknown" ]; then
    echo "- **Model Type**: ${model_type}" >> "$doc_file"
  fi
  
  # Continue with the rest of the documentation
  cat >> "$doc_file" << EOF

## Description

${description}

## Usage

### Running the model

To run this llamafile:

\`\`\`bash
chmod +x ${output_file##*/}  # Only needed the first time
./${output_file##*/}         # Start the web server
\`\`\`

### Command line options

You can also run the model with various command line options:

\`\`\`bash
# Start with a specific prompt
./${output_file##*/} -p "Write a story about..."

# Run in server mode with specific host/port
./${output_file##*/} --host 0.0.0.0 --port 8080

# Adjust inference parameters
./${output_file##*/} --temp 0.7 --top-p 0.9
\`\`\`

For a complete list of options, run:

\`\`\`bash
./${output_file##*/} --help
\`\`\`

## About llamafile

This file was created using [llamafile](https://github.com/Mozilla-Ocho/llamafile), which allows distributing and running LLMs with a single file.

Generated on: $(date)
EOF

  echo "Documentation generated successfully!"
}

# Function to build a llamafile
build_llamafile() {
  local input_file="$1"
  local model_name="$2"
  local output_file="$3"
  
  # Check for llamafile and zipalign in bin directory
  local llamafile="$BIN_DIR/llamafile"
  local zipalign="$BIN_DIR/zipalign"
  
  # Additional search paths for binaries
  if [ ! -x "$llamafile" ]; then
    # Check in typical Homebrew paths
    for dir in "/usr/local/bin" "/opt/homebrew/bin" "$(brew --prefix 2>/dev/null)/bin"; do
      if [ -x "$dir/llamafile" ]; then
        llamafile="$dir/llamafile"
        break
      fi
    done
  fi
  
  if [ ! -x "$zipalign" ]; then
    # Check in typical Homebrew paths
    for dir in "/usr/local/bin" "/opt/homebrew/bin" "$(brew --prefix 2>/dev/null)/bin"; do
      if [ -x "$dir/zipalign" ]; then
        zipalign="$dir/zipalign"
        break
      fi
    done
  fi
  
  if [ ! -x "$llamafile" ]; then
    echo "Error: 'llamafile' executable not found"
    echo "Please ensure MakeLlamafile is properly installed"
    exit 1
  fi
  
  if [ ! -x "$zipalign" ]; then
    echo "Error: 'zipalign' executable not found"
    echo "Please ensure MakeLlamafile is properly installed"
    exit 1
  fi
  
  echo "Creating llamafile $output_file from $input_file..."
  echo "Using llamafile binary: $llamafile"
  echo "Using zipalign binary: $zipalign"
  
  # Create output directory
  mkdir -p "$(dirname "$output_file")"
  
  # Copy the llamafile executable
  cp "$llamafile" "$output_file"
  
  # Create .args file with default arguments
  echo "Creating arguments file..."
  cat > ".args" << EOF
-m
$(basename "$input_file")
--host
0.0.0.0
EOF
  
  # Use zipalign to embed the model and args
  echo "Embedding model and arguments using zipalign..."
  "$zipalign" -j0 "$output_file" "$input_file" ".args"
  
  # Make the llamafile executable
  chmod +x "$output_file"
  
  # Clean up temporary files
  rm -f ".args"
  
  echo "llamafile creation complete!"
}

# Function to test the llamafile
test_llamafile() {
  local llamafile_path="$1"
  local prompt="${2:-Tell me a short story}"
  
  echo "Testing llamafile with prompt: '$prompt'"
  echo "==============================================="
  
  # Run the llamafile with the prompt and a reasonable generation length
  "$llamafile_path" -e -p "$prompt" -n 150 2>/dev/null
  
  local result=$?
  echo "==============================================="
  
  if [ $result -eq 0 ]; then
    echo "Test successful!"
  else
    echo "Test failed! Exit code: $result"
  fi
}

# Parse command line arguments
model_name=""
description=""
output_dir="$OUTPUT_DIR"
test_model=false
test_prompt="Tell me a short story"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_usage
      exit 0
      ;;
    -o|--output-dir)
      output_dir="$2"
      shift 2
      ;;
    -n|--name)
      model_name="$2"
      shift 2
      ;;
    -d|--description)
      description="$2"
      shift 2
      ;;
    -t|--test)
      test_model=true
      shift
      ;;
    -p|--prompt)
      test_prompt="$2"
      test_model=true
      shift 2
      ;;
    -*)
      echo "Unknown option: $1"
      show_usage
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

# Check if we have an input file
if [ $# -eq 0 ]; then
  echo "Error: No input file specified"
  show_usage
  exit 1
fi

input="$1"
input_file=""

# Check if input is a URL or local file
if [[ "$input" == http* ]]; then
  echo "Downloading from URL: $input"
  input_file="$(download_file "$input")"
  downloaded=true
else
  input_file="$input"
  if [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' not found"
    exit 1
  fi
  downloaded=false
fi

# Set model name if not provided
if [ -z "$model_name" ]; then
  model_name="$(basename "${input_file%.gguf}")"
fi

# Set output filename
output_file="${output_dir}/${model_name}/${model_name}.llamafile"

# Calculate SHA256 hash
hash=$(calculate_hash "$input_file")
echo "SHA256 Hash: $hash"

# Extract model information
model_info=$(extract_model_info "$input_file")

# Build the llamafile
build_llamafile "$input_file" "$model_name" "$output_file"

# Generate documentation
generate_docs "$model_name" "$input_file" "$output_file" "$hash" "$description" "$model_info"

# Test the llamafile if requested
if [ "$test_model" = true ]; then
  test_llamafile "$output_file" "$test_prompt"
fi

# Clean up downloaded file if needed
if [ "$downloaded" = true ]; then
  echo "Cleaning up downloaded file..."
  rm -f "$input_file"
fi

echo "Successfully created llamafile at $output_file"
echo "Documentation available at ${output_dir}/${model_name}/README.md" 