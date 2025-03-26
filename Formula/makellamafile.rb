class Makellamafile < Formula
  desc "Converter for turning LLM files into self-contained executables on macOS"
  homepage "https://github.com/sebk4c/MakeLlamafile"
  url "https://github.com/sebk4c/MakeLlamafile/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
  license "MIT"
  
  depends_on "curl"
  depends_on :macos => :monterey
  depends_on :arch => :arm64
  
  def install
    # Install scripts
    bin.install "create_llamafile.sh" => "makellamafile"
    
    # Create package-specific directories in the Homebrew prefix
    share_path = "#{prefix}/share/makellamafile"
    mkdir_p "#{share_path}/bin"
    mkdir_p "#{share_path}/models"
    
    # Download binaries for llamafile tools
    system "curl", "-L", "-o", "#{share_path}/bin/llamafile", "https://github.com/Mozilla-Ocho/llamafile/releases/download/0.9.1/llamafile-0.9.1"
    system "curl", "-L", "-o", "#{share_path}/bin/zipalign", "https://github.com/Mozilla-Ocho/llamafile/releases/download/0.9.1/zipalign-0.9.1"
    chmod 0755, "#{share_path}/bin/llamafile"
    chmod 0755, "#{share_path}/bin/zipalign"
    
    # Check for existing test model in llamafile repository
    test_model_path = ""
    [
      "dependencies/llamafile/models/TinyLLama-v0.1-5M-F16.gguf",
      "models/TinyLLama-v0.1-5M-F16.gguf"
    ].each do |path|
      if File.exist?(path)
        test_model_path = path
        break
      end
    end
    
    # Copy or download the test model
    if test_model_path.empty?
      # Download test model (tiny size for quick testing)
      system "curl", "-L", "-o", "#{share_path}/models/TinyLLama-v0.1-5M-F16.gguf", "https://huggingface.co/ggml-org/models/resolve/main/TinyLLama-v0.1-5M-F16.gguf"
    else
      # Copy existing test model
      system "cp", test_model_path, "#{share_path}/models/TinyLLama-v0.1-5M-F16.gguf"
    end
    
    # Create symlinks in bin directory
    bin.install_symlink "#{share_path}/bin/llamafile"
    bin.install_symlink "#{share_path}/bin/zipalign"
    
    # Copy setup script to share directory
    share_path.install "setup.sh"
    
    # Copy README and other documentation
    doc.install "README.md"
    doc.install "LICENSE"
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