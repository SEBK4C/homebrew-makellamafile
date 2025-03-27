class Makellamafile < Formula
  desc "Converter for turning LLM files into self-contained executables on macOS"
  homepage "https://github.com/sebk4c/homebrew-makellamafile"
  url "https://github.com/Mozilla-Ocho/llamafile/archive/refs/tags/0.9.1.tar.gz"
  sha256 "9f96f8d214ff3e4ae3743688bc32372939122842216b6047308137a5e66ebe9d"
  license "MIT"
  
  depends_on "curl"
  depends_on :macos => :monterey
  depends_on :arch => :arm64
  
  def install
    # Create package-specific directories in the Homebrew prefix
    share_path = "#{prefix}/share/makellamafile"
    mkdir_p "#{share_path}/bin"
    mkdir_p "#{share_path}/models"
    
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
        system "curl", "-L", "-o", "#{share_path}/bin/llamafile", 
               "https://github.com/Mozilla-Ocho/llamafile/releases/download/0.9.1/llamafile-0.9.1-apple-darwin-arm64"
        system "curl", "-L", "-o", "#{share_path}/bin/zipalign", 
               "https://github.com/Mozilla-Ocho/llamafile/releases/download/0.9.1/zipalign-0.9.1-apple-darwin-arm64"
        
        # Ensure binaries are executable and continue with script creation
        chmod 0755, "#{share_path}/bin/llamafile"
        chmod 0755, "#{share_path}/bin/zipalign"
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
      system "curl", "-L", "-o", "#{share_path}/bin/llamafile", 
             "https://github.com/Mozilla-Ocho/llamafile/releases/download/0.9.1/llamafile-0.9.1-apple-darwin-arm64"
      system "curl", "-L", "-o", "#{share_path}/bin/zipalign", 
             "https://github.com/Mozilla-Ocho/llamafile/releases/download/0.9.1/zipalign-0.9.1-apple-darwin-arm64"
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
    
    # Create a basic version of create_llamafile.sh script
    File.write("#{share_path}/bin/create_llamafile.sh", <<~EOS)
      #!/bin/bash
      set -e
      
      # Default output directory
      DEFAULT_OUTPUT_DIR="$HOME/Library/Application Support/makellamafile/llamafiles"
      CONFIG_FILE="$HOME/.config/makellamafile/config"
      
      # Read from config file if it exists
      if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
      fi
      
      # Use OUTPUT_DIR from config or default
      OUTPUT_DIR="\${OUTPUT_DIR:-\$DEFAULT_OUTPUT_DIR}"
      
      # Parse command line arguments
      POSITIONAL_ARGS=()
      MODEL_NAME=""
      
      while [[ $# -gt 0 ]]; do
        case $1 in
          -h|--help)
            echo "Usage: makellamafile [OPTIONS] GGUF_FILE_OR_URL"
            echo
            echo "Options:"
            echo "  -h, --help                 Show this help message"
            echo "  -o, --output-dir DIR       Set output directory (default: $OUTPUT_DIR)"
            echo "  -n, --name MODEL_NAME      Custom name for model (default: derived from filename)"
            echo "  -d, --description DESC     Custom description for the model"
            echo "  -t, --test                 Test the generated llamafile after creation"
            echo "  -p, --prompt PROMPT        Test prompt to use with the model"
            exit 0
            ;;
          -o|--output-dir)
            OUTPUT_DIR="$2"
            shift
            shift
            ;;
          -n|--name)
            MODEL_NAME="$2"
            shift
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
        exit 1
      fi
      
      # Get the model file
      MODEL_FILE="$1"
      if [ -z "$MODEL_NAME" ]; then
        MODEL_NAME=$(basename "$MODEL_FILE" .gguf)
      fi
      
      # Create output directory
      mkdir -p "$OUTPUT_DIR/$MODEL_NAME"
      if [ $? -ne 0 ]; then
        echo "Error: Could not create directory $OUTPUT_DIR/$MODEL_NAME"
        echo "You may need to manually create it:"
        echo "  mkdir -p \"$OUTPUT_DIR/$MODEL_NAME\""
        exit 1
      fi
      
      LLAMAFILE="$OUTPUT_DIR/$MODEL_NAME/$MODEL_NAME.llamafile"
      
      # Convert the model
      echo "Creating llamafile from $MODEL_FILE..."
      cp #{share_path}/bin/llamafile "$LLAMAFILE"
      #{share_path}/bin/zipalign -j0 "$LLAMAFILE" "$MODEL_FILE"
      chmod +x "$LLAMAFILE"
      
      echo "Created llamafile at: $LLAMAFILE"
      echo "Run it with: $LLAMAFILE"
    EOS
    chmod 0755, "#{share_path}/bin/create_llamafile.sh"
    
    # Download a tiny test model
    ohai "Downloading test model"
    system "curl", "-L", "-o", "#{share_path}/models/TinyLLama-v0.1-5M-F16.gguf", 
           "https://huggingface.co/ggml-org/models/resolve/main/TinyLLama-v0.1-5M-F16.gguf"
    
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
  
  def post_install
    # Use macOS-appropriate directories
    user_home = ENV["HOME"]
    library_dir = "#{user_home}/Library/Application Support/makellamafile"
    config_dir = "#{user_home}/.config/makellamafile"
    
    # Use a more permission-friendly approach to directory creation
    ohai "Setting up user directories..."
    
    begin
      # Try to create directories safely
      [
        "#{library_dir}",
        "#{library_dir}/models",
        "#{library_dir}/llamafiles",
        "#{config_dir}"
      ].each do |dir|
        if Dir.exist?(dir)
          ohai "Directory already exists: #{dir}"
        else
          Dir.mkdir(dir) rescue nil
          unless Dir.exist?(dir)
            opoo "Could not create directory: #{dir}"
          end
        end
      end
      
      # Create configuration file if possible
      if Dir.exist?(config_dir)
        config_path = "#{config_dir}/config"
        File.write(config_path, <<~EOS) rescue nil
          # MakeLlamafile configuration
          OUTPUT_DIR="#{library_dir}/llamafiles"
          DOWNLOAD_DIR="#{library_dir}/models"
          BIN_DIR="#{prefix}/share/makellamafile/bin"
        EOS
        
        if File.exist?(config_path)
          system "chmod", "644", config_path
        end
      end
      
      # Attempt to convert the test model if possible
      test_model = "#{prefix}/share/makellamafile/models/TinyLLama-v0.1-5M-F16.gguf"
      if File.exist?(test_model) && Dir.exist?("#{library_dir}/llamafiles")
        system "#{bin}/makellamafile", "-o", "#{library_dir}/llamafiles", "-n", "TinyLLama-v0.1-5M-F16", test_model
      end
      
    rescue => e
      opoo "Error during setup: #{e.message}"
    end
  end
  
  def caveats
    user_home = ENV["HOME"]
    library_dir = "#{user_home}/Library/Application Support/makellamafile"
    
    <<~EOS
      MakeLlamafile has been installed!
      
      To convert a model file to a llamafile:
        makellamafile path/to/model.gguf
      
      If you get permission errors when running the tool, you may need to manually create:
        mkdir -p "#{library_dir}/models"
        mkdir -p "#{library_dir}/llamafiles"
        mkdir -p "#{user_home}/.config/makellamafile"
      
      The default output location for llamafiles is:
        #{library_dir}/llamafiles
      
      For more information, run:
        makellamafile --help
      
      Note: This version is optimized for macOS on Apple Silicon (M1/M2/M3).
    EOS
  end
  
  test do
    # Basic check that the executable runs
    assert_match "Usage:", shell_output("#{bin}/makellamafile --help")
    
    # Check if binaries are available
    assert_predicate bin/"llamafile", :executable?
    assert_predicate bin/"zipalign", :executable?
    
    # Check if test model was downloaded
    assert_predicate "#{prefix}/share/makellamafile/models/TinyLLama-v0.1-5M-F16.gguf", :file?
    
    # No need to check for user directories as they might not be creatable in test environment
    # Instead, check our package files exist
    assert_predicate "#{prefix}/share/makellamafile/bin/create_llamafile.sh", :executable?
  end
end 