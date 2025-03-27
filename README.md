# MakeLlamafile

A macOS-optimized converter for turning any model.GGUF file into a self-contained executable with a web server interface. Built on Mozilla's llamafile technology for portable AI deployment.

![License](https://img.shields.io/badge/license-MIT-blue.svg)

## Overview

MakeLlamafile simplifies the process of converting large language model files (GGUF format) into standalone executables that can be run on macOS. The resulting llamafile is a single-file executable that includes:

- The model weights
- A built-in web server with chat interface
- Command-line interface

## Features

- Simple command-line interface for converting models
- Automatic downloading of models from Hugging Face
- Documentation generation for each converted model
- Optional testing of generated llamafiles

## Requirements

### Supported Operating Systems
- macOS (Apple Silicon/M1/M2/M3)

### Dependencies
- Installed automatically via Homebrew

## Installation

### Using Homebrew

```bash
# Add the tap repository
brew tap sebk4c/makellamafile

# Install the formula
brew install makellamafile
```

### First-Time Setup (Required)

After installation, you must run the setup command:

```bash
makellamafile --setup
```

This will create the following directories in your home folder:
```
~/models/
  ├── huggingface/    # For downloaded models
  └── llamafiles/     # For generated llamafiles
```

And will create a configuration file at:
```
~/models/MakeLlamafileConfig.txt    # Configuration settings
```

## Usage

### Basic Usage

Convert a local GGUF file to a llamafile:

```bash
makellamafile path/to/model.gguf
```

Convert a model from Hugging Face:

```bash
makellamafile https://huggingface.co/organization/model/resolve/main/model.gguf
```

### Options

```
Usage: makellamafile [OPTIONS] GGUF_FILE_OR_URL

Options:
  -h, --help                 Show this help message
  --setup                    Set up directories and configuration
  -o, --output-dir DIR       Set output directory (default: ~/models/llamafiles)
  -n, --name MODEL_NAME      Custom name for model (default: derived from filename)
  -d, --description DESC     Custom description for the model
  -t, --test                 Test the generated llamafile after creation
  -p, --prompt PROMPT        Test prompt to use with the model
```

## Using Generated Llamafiles

After creating a llamafile, you can run it directly:

```bash
~/models/llamafiles/model-name/model-name.llamafile
```

Your web browser will open automatically to the chat interface (typically at http://localhost:8080).

## Configuration

The configuration file at `~/models/MakeLlamafileConfig.txt` allows you to customize:

- Output directory for converted models
- Download directory for Hugging Face models
- Default parameters for all llamafile conversions

You can edit this file with any text editor to customize your settings.

## File Locations

When installed via Homebrew, the files are organized as follows:

```
/opt/homebrew/bin/makellamafile     # Main executable script (or /usr/local/bin on Intel Macs)
/opt/homebrew/bin/llamafile         # Symlink to Mozilla llamafile binary
/opt/homebrew/bin/zipalign          # Symlink to Mozilla zipalign binary

/opt/homebrew/share/makellamafile/  # Package data directory
  ├── bin/                      # Binary storage
  │   ├── llamafile             # Mozilla llamafile binary
  │   └── zipalign              # Mozilla zipalign binary
  └── models/                   # Test model storage
      └── TinyLLama-v0.1-5M-F16.gguf # Small test model

~/models/                       # User's model storage (created by --setup)
  ├── huggingface/              # Downloads from Hugging Face
  ├── llamafiles/               # Generated llamafiles and output
  └── MakeLlamafileConfig.txt   # User configuration file
```

On Intel Macs, Homebrew typically installs to `/usr/local/` instead of `/opt/homebrew/`.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [Mozilla-Ocho/llamafile](https://github.com/Mozilla-Ocho/llamafile) - The underlying technology
- [llama.cpp](https://github.com/ggerganov/llama.cpp) - The backbone of llamafile
- Hugging Face - For hosting the model files
