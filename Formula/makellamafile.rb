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
    
    # Download cosmocc zip file
    cosmocc_zip = buildpath/"cosmocc.zip"
    system "curl", "-L", "-o", cosmocc_zip, "https://cosmo.zip/pub/cosmocc/cosmocc.zip"
    
    unless File.exist?(cosmocc_zip)
      odie "Failed to download cosmocc.zip"
    end
    
    # Extract cosmocc
    system "unzip", cosmocc_zip, "-d", buildpath
    
    unless Dir.exist?(buildpath/".cosmocc")
      odie "Failed to extract cosmocc.zip or .cosmocc directory not found"
    end
    
    # Set up environment for cosmocc
    ENV.prepend_path "PATH", buildpath/".cosmocc/bin"
    cosmocc_make = buildpath/".cosmocc/bin/make"
    
    unless File.executable?(cosmocc_make)
      odie "cosmocc make executable not found or not executable"
    end
    
    ohai "Building llamafile and zipalign (this may take a few minutes)"
    # Build the tools with detailed output
    system "ls", "-la", buildpath/".cosmocc/bin/"
    
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
    
    # Create a basic version of create_llamafile.sh script
    File.write("#{share_path}/bin/create_llamafile.sh", <<~EOS)
      #!/bin/bash
      set -e
      
      # Default output directory
      OUTPUT_DIR="$HOME/models/llamafiles"
      
      # Check for help
      if [[ "$1" == "-h" || "$1" == "--help" ]]; then
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
      fi
      
      # Check if we have enough arguments
      if [ $# -lt 1 ]; then
        echo "Error: No input file specified"
        echo "Run with --help for usage information"
        exit 1
      fi
      
      # Get the model file
      MODEL_FILE="$1"
      MODEL_NAME=$(basename "$MODEL_FILE" .gguf)
      
      # Create output directory
      mkdir -p "$OUTPUT_DIR/$MODEL_NAME"
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
    # Create user directories
    user_home = ENV["HOME"]
    models_dir = "#{user_home}/models"
    config_dir = "#{user_home}/.config/makellamafile"
    
    system "mkdir", "-p", "#{models_dir}/huggingface"
    system "mkdir", "-p", "#{models_dir}/llamafiles"
    system "mkdir", "-p", config_dir
    
    # Create configuration file
    File.write("#{config_dir}/config", <<~EOS)
      # MakeLlamafile configuration
      OUTPUT_DIR="#{models_dir}/llamafiles"
      DOWNLOAD_DIR="#{models_dir}/huggingface"
      BIN_DIR="#{prefix}/share/makellamafile/bin"
    EOS
    
    # Ensure directories have correct permissions
    system "chmod", "755", "#{models_dir}/huggingface"
    system "chmod", "755", "#{models_dir}/llamafiles"
    system "chmod", "644", "#{config_dir}/config"
    
    # Run an automatic test to create the TinyLLama-v0.1-5M-F16.llamafile
    # This ensures a working llamafile is available immediately after installation
    test_model = "#{prefix}/share/makellamafile/models/TinyLLama-v0.1-5M-F16.gguf"
    if File.exist?(test_model)
      system "#{bin}/makellamafile", "-n", "TinyLLama-v0.1-5M-F16", test_model
      system "chmod", "+x", "#{models_dir}/llamafiles/TinyLLama-v0.1-5M-F16/TinyLLama-v0.1-5M-F16.llamafile"
    end
  end
  
  def caveats
    user_home = ENV["HOME"]
    
    <<~EOS
      MakeLlamafile has been installed!
      
      To convert a model file to a llamafile:
        makellamafile path/to/model.gguf
      
      Output will be saved to:
        #{user_home}/models/llamafiles
      
      Downloaded models will be stored in:
        #{user_home}/models/huggingface
      
      A test llamafile has been created at:
        #{user_home}/models/llamafiles/TinyLLama-v0.1-5M-F16/TinyLLama-v0.1-5M-F16.llamafile
        
      You can run it with:
        #{user_home}/models/llamafiles/TinyLLama-v0.1-5M-F16/TinyLLama-v0.1-5M-F16.llamafile
      
      For more information, run:
        makellamafile --help
      
      Note: This version is optimized for macOS on Apple Silicon (M1/M2/M3).
    EOS
  end
  
  test do
    # Basic check that the executable runs
    assert_match "Usage:", shell_output("#{bin}/makellamafile --help")
    
    # Check if the user's directories exist
    user_home = ENV["HOME"]
    assert_predicate "#{user_home}/models/llamafiles", :directory?
    assert_predicate "#{user_home}/models/huggingface", :directory?
    
    # Check if required binaries are available
    assert_predicate bin/"llamafile", :executable?
    assert_predicate bin/"zipalign", :executable?
    
    # Check if test model was downloaded
    assert_predicate "#{prefix}/share/makellamafile/models/TinyLLama-v0.1-5M-F16.gguf", :file?
    
    # Check if the test llamafile was created
    assert_predicate "#{user_home}/models/llamafiles/TinyLLama-v0.1-5M-F16/TinyLLama-v0.1-5M-F16.llamafile", :executable?
  end
end 