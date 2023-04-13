#=
    .configure_pycall_in_conda.jl

A script for automatically configuring SpineInterface PyCall inside a Conda environment.

NOTE! This script needs to be run from Julia inside an active Conda environment with
`spinedb_api`! (e.g. the one included in a Spine Toolbox installation)
=#

# Activate the SpineInterface module in this directory.
using Pkg 
Pkg.activate(@__DIR__)

# Set PyCall "PYTHON" based on active Conda "CONDA_PREFIX" environment.
ENV["PYTHON"] = ENV["CONDA_PREFIX"] * "\\python.exe"
# Install SpineInterface dependencies
Pkg.instantiate()
# Re-build PyCall just to be sure
Pkg.build("PyCall")