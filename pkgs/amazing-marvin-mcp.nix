{
  lib,
  python3Packages,
  fetchPypi,
}:

# Amazing Marvin MCP server (https://github.com/bgheneti/Amazing-Marvin-MCP).
#
# Not in nixpkgs, and the upstream install path is `pipx install
# amazing-marvin-mcp` / `uvx`, which both want to resolve and build wheels at
# runtime. That is exactly what this repo does not do: the openclaw host runs
# the MCP server as a child process of the gateway, so it has to exist in the
# closure before the gateway starts, not be fetched on first use.
#
# Every dependency is already in nixpkgs, so this is a plain sdist build. The
# upstream bounds are all `>=`, so nothing needs relaxing — but note the jump
# from the declared `fastmcp>=0.1.0` to nixpkgs' 3.x: the package only uses
# `FastMCP(name=...)`, the `@mcp.tool()` decorator and `mcp.run()`, which are
# stable across that range. If a future fastmcp bump breaks it, that is the
# first thing to check.
#
# `fastapi` and `uvicorn` are declared by upstream but unused by the stdio
# entry point. They stay in propagatedBuildInputs so the dist-info runtime
# dependency check passes rather than being patched out.
python3Packages.buildPythonApplication rec {
  pname = "amazing-marvin-mcp";
  version = "1.0.1";
  pyproject = true;

  src = fetchPypi {
    pname = "amazing_marvin_mcp";
    inherit version;
    hash = "sha256-YMuvDdZlSTElJNNpSf1nDWcF7lnyS/OpfSWdNmT+OV0=";
  };

  build-system = [ python3Packages.setuptools ];

  dependencies = with python3Packages; [
    fastapi
    fastmcp
    pydantic
    pydantic-settings
    python-dotenv
    requests
    uvicorn
  ];

  # No tests in the sdist; the import check is the real smoke test — it is what
  # catches a fastmcp API break at build time instead of at first Telegram
  # message.
  doCheck = false;
  pythonImportsCheck = [ "amazing_marvin_mcp.main" ];

  meta = {
    description = "Model Context Protocol server for the Amazing Marvin task manager";
    homepage = "https://github.com/bgheneti/Amazing-Marvin-MCP";
    license = lib.licenses.mit;
    mainProgram = "amazing-marvin-mcp";
  };
}
