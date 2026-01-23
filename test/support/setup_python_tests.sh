#!/bin/bash
# Setup script for zarr-python integration tests

set -e

echo "Setting up Python dependencies for integration tests..."

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed."
    echo "Please install Python 3.6 or later."
    exit 1
fi

echo "Python version: $(python3 --version)"

# Install dependencies
echo "Installing zarr-python and numpy..."
python3 -m pip install -r "$(dirname "$0")/requirements.txt"

# Verify installation
echo "Verifying installation..."
python3 -c "import zarr; import numpy; print('zarr version:', zarr.__version__); print('numpy version:', numpy.__version__)"

echo "Setup complete! You can now run integration tests with:"
echo "  mix test test/ex_zarr_python_integration_test.exs"
