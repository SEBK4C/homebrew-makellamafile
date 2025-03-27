class Makellamafile < Formula
  desc "Converter for turning LLM files into self-contained executables on macOS"
  homepage "https://github.com/sebk4c/homebrew-makellamafile"
  url "https://github.com/Mozilla-Ocho/llamafile/archive/refs/tags/0.9.1.tar.gz"
  sha256 "9f96f8d214ff3e4ae3743688bc32372939122842216b6047308137a5e66ebe9d"
  license "MIT"
  
  depends_on "curl"
  depends_on "huggingface-cli"
  depends_on :macos => :monterey
  depends_on :arch => :arm64
  
  def install
    # Create package-specific directories in the Homebrew prefix
    share_path = "#{prefix}/share/makellamafile"
    mkdir_p "#{share_path}/bin"
    
    ohai "Setting up cosmocc compiler environment"
    # Download and set up cosmocc explicitly with better error handling
    ENV["TMPDIR"] = buildpath/"tmp"
    mkdir_p ENV["TMPDIR"]
    
    # Create a separate directory for cosmocc to avoid conflicts
    cosmocc_dir = buildpath/".cosmocc"
    mkdir_p cosmocc_dir
    
    # Download cosmocc zip file
    cosmocc_zip = buildpath/"cosmocc.zip"
    system "curl", "-L", "-o", cosmocc_zip, "https://cosmo.zip/pub/cosmocc/cosmocc.zip"
    
    unless File.exist?(cosmocc_zip)
      odie "Failed to download cosmocc.zip"
    end
    
    # Extract cosmocc to the dedicated directory
    ohai "Extracting cosmocc.zip to #{cosmocc_dir}"
    system "unzip", "-q", cosmocc_zip, "-d", cosmocc_dir
    
    # Check if the extraction worked by looking for bin/make
    cosmocc_make = cosmocc_dir/"bin/make"
    
    unless File.executable?(cosmocc_make)
      # If not found in expected location, try different approach - sometimes cosmocc.zip contents are at root
      if File.exist?(cosmocc_dir/"cosmocc")
        ohai "Found cosmocc in different location structure"
        cosmocc_make = cosmocc_dir/"cosmocc/bin/make"
      else
        # Skip building and just download pre-built binaries
        ohai "Unable to set up cosmocc properly, downloading pre-built binaries instead"
        download_binaries(share_path)
        goto :create_script
      end
    end
    
    # Set up environment for cosmocc
    ENV.prepend_path "PATH", cosmocc_make.dirname
    
    ohai "Building llamafile and zipalign (this may take a few minutes)"
    # Build the tools with detailed output
    system "ls", "-la", cosmocc_make.dirname
    
    # Try building with verbose output to see potential errors
    system cosmocc_make, "-j#{ENV.make_jobs}", "V=1", "o/llamafile", "o/zipalign"
    
    unless File.exist?(buildpath/"o/llamafile") && File.exist?(buildpath/"o/zipalign")
      # If build fails, try alternative approach: download pre-built binaries
      ohai "Build from source failed, downloading pre-built binaries instead"
      download_binaries(share_path)
    else
      # Install the successfully built binaries
      cp buildpath/"o/llamafile", "#{share_path}/bin/llamafile"
      cp buildpath/"o/zipalign", "#{share_path}/bin/zipalign"
    end
    
    # Ensure binaries are executable
    chmod 0755, "#{share_path}/bin/llamafile"
    chmod 0755, "#{share_path}/bin/zipalign"
    
    # Create script label for goto
    create_script = true
    
    # Create an enhanced version of create_llamafile.sh script
    File.write("#{share_path}/bin/create_llamafile.sh", <<~EOS)
      #!/bin/bash
      set -e
      
      # Default output directory
      DEFAULT_OUTPUT_DIR="$HOME/models/llamafiles"
      MODELS_DIR="$HOME/models"
      CONFIG_FILE="$MODELS_DIR/MakeLlamafileConfig.txt"
      
      # Set Homebrew binary paths
      BIN_DIR="#{share_path}/bin"
      LLAMAFILE="$BIN_DIR/llamafile"
      ZIPALIGN="$BIN_DIR/zipalign"
      
      # Read from config file if it exists
      if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
      fi
      
      # Use OUTPUT_DIR from config or default
      OUTPUT_DIR="\${OUTPUT_DIR:-\$DEFAULT_OUTPUT_DIR}"
      DOWNLOAD_DIR="\${DOWNLOAD_DIR:-\$MODELS_DIR/huggingface}"
      
      # Function to set up directories and config
      setup_directories() {
        echo "Setting up MakeLlamafile directories..."
        
        # Create main directories
        mkdir -p "$MODELS_DIR"
        mkdir -p "$MODELS_DIR/llamafiles"
        mkdir -p "$MODELS_DIR/huggingface"
        
        # Create config file with instructions if it doesn't exist
        if [ ! -f "$CONFIG_FILE" ]; then
          cat > "$CONFIG_FILE" << CONFIG_CONTENT
# MakeLlamafile Configuration File
# --------------------------------
# This file controls the default settings for the MakeLlamafile tool.
# You can edit this file to customize how your models are converted.

# Directory where converted llamafiles will be stored
OUTPUT_DIR="$MODELS_DIR/llamafiles"

# Directory where downloaded models will be stored
DOWNLOAD_DIR="$MODELS_DIR/huggingface"

# Default llamafile parameters (applied to all conversions)
# Examples:
# LLAMAFILE_ARGS="--chat-template chatml --chat --n-gpu-layers 35"
# LLAMAFILE_ARGS="--threads 4 --ctx-size 4096"
LLAMAFILE_ARGS=""

CONFIG_CONTENT
          echo "Created configuration file at: $CONFIG_FILE"
        fi
        
        echo "Setup complete! Your models will be stored in:"
        echo "  - Downloaded models: $MODELS_DIR/huggingface"
        echo "  - Converted llamafiles: $MODELS_DIR/llamafiles"
        echo ""
        echo "You can customize settings in: $CONFIG_FILE"
        exit 0
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
        
        # Actually download the file
        curl -L --output "$output_file" "$url"
        
        # Check if download was successful
        if [ ! -f "$output_file" ]; then
          echo "Error: Download failed"
          exit 1
        fi
        
        echo "Download complete: $output_file"
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
        local doc_file="${OUTPUT_DIR}/${model_name}/README.md"
        
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
        
        echo "Creating llamafile $output_file from $input_file..."
        
        # Make sure the input file exists
        if [ ! -f "$input_file" ]; then
          echo "Error: Input file not found: $input_file"
          exit 1
        fi
        
        # Create output directory
        mkdir -p "$(dirname "$output_file")"
        
        # Copy the llamafile executable
        cp "$LLAMAFILE" "$output_file"
        
        # Check if the copy was successful
        if [ ! -f "$output_file" ]; then
          echo "Error: Failed to create llamafile at $output_file"
          exit 1
        fi
        
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
        "$ZIPALIGN" -j0 "$output_file" "$input_file" ".args"
        
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
      
      # Function to find next available version number for a model directory
      find_next_version() {
        local base_name="$1"
        local dir="$2"
        local counter=1
        
        if [ ! -d "${dir}/${base_name}" ]; then
          echo "$base_name"
          return
        fi
        
        while [ -d "${dir}/${base_name}_v${counter}" ]; do
          counter=$((counter + 1))
        done
        
        echo "${base_name}_v${counter}"
      }
      
      # Parse command line arguments
      POSITIONAL_ARGS=()
      model_name=""
      description=""
      test_model=false
      test_prompt="Tell me a short story"
      no_docs=false
      
      while [[ $# -gt 0 ]]; do
        case $1 in
          -h|--help)
            echo "Usage: makellamafile [OPTIONS] GGUF_FILE_OR_URL"
            echo
            echo "Options:"
            echo "  -h, --help                 Show this help message"
            echo "  --setup                    Set up directories and configuration"
            echo "  -o, --output-dir DIR       Set output directory (default: $OUTPUT_DIR)"
            echo "  -n, --name MODEL_NAME      Custom name for model (default: derived from filename)"
            echo "  -d, --description DESC     Custom description for the model"
            echo "  -t, --test                 Test the generated llamafile after creation"
            echo "  -p, --prompt PROMPT        Test prompt to use with the model"
            echo "  --no-docs                  Skip generating documentation"
            exit 0
            ;;
          --setup)
            setup_directories
            ;;
          -o|--output-dir)
            OUTPUT_DIR="$2"
            shift
            shift
            ;;
          -n|--name)
            model_name="$2"
            shift
            shift
            ;;
          -d|--description)
            description="$2"
            shift
            shift
            ;;
          -t|--test)
            test_model=true
            shift
            ;;
          -p|--prompt)
            test_prompt="$2"
            test_model=true
            shift
            shift
            ;;
          --no-docs)
            no_docs=true
            shift
            ;;
          *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
        esac
      done
      
      set -- "\${POSITIONAL_ARGS[@]}"
      
      # Check if we have enough arguments
      if [ $# -lt 1 ]; then
        echo "Error: No input file specified"
        echo "Run with --help for usage information"
        echo ""
        echo "Need to set up directories first? Run:"
        echo "  makellamafile --setup"
        exit 1
      fi
      
      # Check if output directory exists, suggest setup if not
      if [ ! -d "$OUTPUT_DIR" ]; then
        echo "Error: Output directory $OUTPUT_DIR does not exist"
        echo "Please run setup first:"
        echo "  makellamafile --setup"
        exit 1
      fi
      
      # Check if binaries exist and are executable
      if [ ! -f "$LLAMAFILE" ] || [ ! -x "$LLAMAFILE" ]; then
        echo "Error: llamafile binary not found or not executable at $LLAMAFILE"
        echo "Please ensure MakeLlamafile is properly installed"
        exit 1
      fi
      
      if [ ! -f "$ZIPALIGN" ] || [ ! -x "$ZIPALIGN" ]; then
        echo "Error: zipalign binary not found or not executable at $ZIPALIGN"
        echo "Please ensure MakeLlamafile is properly installed"
        exit 1
      fi
      
      # Get the model file
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
      
      # Check if directory already exists and increment version if needed
      model_name="$(find_next_version "$model_name" "$OUTPUT_DIR")"
      echo "Using model name: $model_name"
      
      # Set output filename
      output_file="${OUTPUT_DIR}/${model_name}/${model_name}.llamafile"
      
      # Calculate SHA256 hash
      hash=$(calculate_hash "$input_file")
      echo "SHA256 Hash: $hash"
      
      # Extract model information
      model_info=$(extract_model_info "$input_file")
      
      # Build the llamafile
      build_llamafile "$input_file" "$model_name" "$output_file"
      
      # Generate documentation unless disabled
      if [ "$no_docs" = false ]; then
        generate_docs "$model_name" "$input_file" "$output_file" "$hash" "$description" "$model_info"
      fi
      
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
      
      if [ "$no_docs" = false ]; then
        echo "Documentation available at ${OUTPUT_DIR}/${model_name}/README.md"
      fi
    EOS
    chmod 0755, "#{share_path}/bin/create_llamafile.sh"
    
    # Create symlinks in bin directory
    bin.install_symlink "#{share_path}/bin/llamafile"
    bin.install_symlink "#{share_path}/bin/zipalign"
    bin.install_symlink "#{share_path}/bin/create_llamafile.sh" => "makellamafile"
    
    # Create a simple README if needed
    unless File.exist?("README.md")
      File.write("#{share_path}/README.md", <<~EOS)
        # MakeLlamafile
        
        A macOS-optimized converter for turning GGUF model files into self-contained executables.
        
        ## Usage
        
        ```bash
        makellamafile path/to/model.gguf
        ```
        
        For more information, run:
        ```bash
        makellamafile --help
        ```
      EOS
      doc.install "#{share_path}/README.md"
    else
      doc.install "README.md"
    end
    
    if File.exist?("LICENSE")
      doc.install "LICENSE"
    end
  end
  
  # Helper method to download binary files with validation
  def download_binaries(share_path)
    version = "0.9.1"
    binaries = {
      "llamafile" => "llamafile-#{version}-apple-darwin-arm64",
      "zipalign" => "zipalign-#{version}-apple-darwin-arm64"
    }
    
    ohai "Downloading pre-built binaries (version #{version})"
    
    binaries.each do |binary_name, file_name|
      binary_path = "#{share_path}/bin/#{binary_name}"
      
      # Download binary with explicit output and show progress
      url = "https://github.com/Mozilla-Ocho/llamafile/releases/download/#{version}/#{file_name}"
      system "curl", "-#", "-L", "-o", binary_path, url
      
      # Verify file was downloaded and has content
      unless File.exist?(binary_path) && File.size(binary_path) > 1000
        odie "Failed to download #{binary_name} from #{url}"
      end
      
      # Set executable permission
      chmod 0755, binary_path
      
      # Basic verification that it's a binary file
      if system "file", binary_path, :out => File::NULL, :err => File::NULL
        output = `file #{binary_path}`
        if output.include?("text") || output.include?("Not Found")
          odie "Downloaded #{binary_name} is not a valid binary file"
        end
      end
      
      ohai "Successfully downloaded #{binary_name}"
    end
  end
  
  def post_install
    ohai "Installation complete. Run 'makellamafile --setup' to set up directories."
  end
  
  def caveats
    <<~EOS
      MakeLlamafile has been installed!
      
      Before using makellamafile, run:
        makellamafile --setup
      
      This will create the necessary directories and configuration file.
      
      Note: This version is optimized for macOS on Apple Silicon (M1/M2/M3).
    EOS
  end
  
  test do
    # Basic check that the executable runs
    assert_match "Usage:", shell_output("#{bin}/makellamafile --help")
    
    # Check if the --setup command works (but don't actually run it since test env can't create dirs)
    assert_match "setup", shell_output("#{bin}/makellamafile --help")
    
    # Check if binaries are available
    assert_predicate bin/"llamafile", :executable?
    assert_predicate bin/"zipalign", :executable?
    
    # Check if our package files exist
    assert_predicate "#{prefix}/share/makellamafile/bin/create_llamafile.sh", :executable?
  end
end 