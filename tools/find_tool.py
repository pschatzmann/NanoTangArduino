"""Locates the external FPGA tools (yosys, nextpnr-himbaechel, gowin_pack,
openFPGALoader) for tools/build_bitstream.py and tools/upload.py.

The Arduino IDE started from the desktop never reads the shell startup file
that puts oss-cad-suite or a conda/venv on PATH, so a tool that is only
reachable that way is invisible to it. Each tool is therefore looked up in
order: its environment variable (e.g. YOSYS=/path/to/yosys), the bin/
folder of the oss-cad-suite-gowin tool Boards Manager installs with the
core (passed as --tools-dir=, see take_tools_dir_arg()), PATH, and then the
folders in TOOL_DIRS where pip/conda/pipx/oss-cad-suite usually put it.
"""
import os
import shutil
import sys
from pathlib import Path

TOOL_DIRS = [
    Path.home() / "oss-cad-suite" / "bin",
    Path.home() / ".local" / "bin",
    Path.home() / "miniconda3" / "bin",
    Path.home() / "miniforge3" / "bin",
    Path.home() / "mambaforge" / "bin",
    Path.home() / "anaconda3" / "bin",
    Path("/opt/oss-cad-suite/bin"),
    Path("/opt/conda/bin"),
]


# bin/ of the tools Boards Manager installed with the core, if any.
bundled_dir = None


def take_tools_dir_arg(argv):
    """Removes a --tools-dir=<dir> option from argv (in place) and searches
    <dir>/bin before PATH. platform.txt passes the oss-cad-suite-gowin
    tool's install folder this way; on an installation that has none (e.g.
    a development checkout), arduino-cli leaves the {runtime.tools...}
    placeholder unexpanded, which isn't a folder and is ignored."""
    global bundled_dir
    for arg in list(argv):
        if arg.startswith("--tools-dir="):
            argv.remove(arg)
            d = Path(arg.split("=", 1)[1]) / "bin"
            if d.is_dir():
                bundled_dir = d
                if os.name == "nt":
                    # What the suite's environment.bat sets up: on Windows,
                    # the programs in bin/ find their DLLs in lib/ only
                    # through PATH (the Linux/macOS bin/ wrappers set up
                    # their own library path).
                    lib = d.parent / "lib"
                    os.environ["PATH"] = f"{d}{os.pathsep}{lib}{os.pathsep}" + os.environ.get("PATH", "")
                    os.environ.setdefault("OPENFPGALOADER_SOJ_DIR", str(d.parent / "share" / "openFPGALoader"))


def bundled_gowin_pack_cmd():
    """The command that runs the bundled tools' gowin_pack, or None. On
    Windows its bin/gowin_pack.exe is a pip launcher that looks for Python
    where the suite was built, so run apycula with the suite's Python."""
    if bundled_dir is None:
        return None
    if os.name == "nt":
        python = bundled_dir.parent / "lib" / "python3.exe"
        return [str(python), "-m", "apycula.gowin_pack"] if python.is_file() else None
    found = find_in(bundled_dir, "gowin_pack")
    return [found] if found else None


def env_var_for(name):
    """The environment variable that overrides a tool's location:
    "nextpnr-himbaechel" -> "NEXTPNR_HIMBAECHEL"."""
    return name.upper().replace("-", "_")


def find_tool(name, fallback_dirs=True):
    """Full path of the tool `name`, or None if it isn't found. With
    fallback_dirs=False, TOOL_DIRS isn't searched."""
    env = os.environ.get(env_var_for(name))
    if env:
        return env
    if bundled_dir:
        found = find_in(bundled_dir, name)
        if found:
            return found
    found = shutil.which(name)
    if found or not fallback_dirs:
        return found
    for d in TOOL_DIRS:
        found = find_in(d, name)
        if found:
            return found
    return None


def find_in(d, name):
    for exe in (name, name + ".exe"):
        candidate = d / exe
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def not_found_message(name, what, install_hint):
    return (
        f"error: {name} ({what}) not found. It is not on PATH (the Arduino "
        "IDE does not read ~/.bashrc, so PATH changes and conda/venv "
        "activations there are not visible) and not in any of: "
        + ", ".join(str(d) for d in TOOL_DIRS)
        + f". {install_hint}, or set the {env_var_for(name)} environment "
        "variable to its full path - see docs/BUILDING.md.")


def require_tool(name, what, install_hint):
    """Like find_tool(), but exits with an explanation if it isn't found."""
    found = find_tool(name)
    if found is None:
        sys.exit(not_found_message(name, what, install_hint))
    return found
