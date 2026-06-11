# ============================================================================
# Makefile — Hermes Alpine ecosystem build/install lifecycle
# ============================================================================
# Targets:
#   install          Full ecosystem install (deps + Hermes + skills + plugins)
#   install-deps     System and Python dependencies only
#   install-agent    Hermes Agent (editable) install only
#   install-skills   Symlink skills from skills/ to ~/.hermes/skills/
#   install-plugins  Symlink plugins from plugins/ to ~/.hermes/plugins/
#   configure-mcp    Merge MCP server config into ~/.hermes/config.yaml
#   integrate        Install full ecosystem (npm MCP, pip, git, wrappers)
#   verify           Verify ecosystem integration
#   update-external  Update npm packages, Python MCP deps, RTK
#   bootstrap        Quick bootstrap: install + integrate + verify
#   help             Show this help
# ============================================================================

SHELL := /bin/bash
.ONESHELL:

SCRIPT_DIR := scripts
HERMES_HOME := $(or $(HERMES_HOME),$(HOME)/.hermes)

.PHONY: help install install-deps install-agent \
        install-skills install-plugins configure-mcp integrate verify \
        update-external bootstrap

help:
	@echo "Hermes Alpine — Ecosystem Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make install          Full ecosystem install"
	@echo "  make install-deps     System + Python deps only"
	@echo "  make install-agent    Hermes Agent editable install"
	@echo "  make install-skills   Symlink skills to ~/.hermes/skills/"
	@echo "  make install-plugins  Symlink plugins to ~/.hermes/plugins/"
	@echo "  make configure-mcp    Merge MCP servers into config.yaml"
	@echo "  make integrate        Install full ecosystem (npm, pip, git)"
	@echo "  make verify           Check integration status"
	@echo "  make update-external  Update npm + Python MCP + RTK"
	@echo "  make bootstrap        Install + integrate + verify"
	@echo ""

# ---- Top-level targets ----

install: install-deps install-agent install-skills install-plugins configure-mcp
	@echo ""
	@echo "✓ Full install complete. Run 'make integrate' for MCP+npm+git deps."

integrate: configure-mcp
	@echo "=== Installing system integrations ==="
	@bash $(SCRIPT_DIR)/install-system-integrations.sh

bootstrap: install integrate
	@echo ""
	@echo "=== Bootstrap: Verification ==="
	@$(SCRIPT_DIR)/verify-integration.sh || true

# ---- Sub-targets ----

install-deps:
	@echo "=== Installing dependencies ==="
	@bash $(SCRIPT_DIR)/setup-ecosystem.sh

install-agent:
	@echo "=== Installing Hermes Agent ==="
	@HERMES_AGENT_DIR="$(CURDIR)/hermes-agent"
	if [ ! -d "$$HERMES_AGENT_DIR/.git" ]; then
		git clone --depth=1 https://github.com/nousresearch/hermes-agent.git "$$HERMES_AGENT_DIR"
	fi
	@if [ -f "$$HERMES_AGENT_DIR/pyproject.toml" ]; then
		sed -i 's/requires-python = ">=3.11,<3.14"/requires-python = ">=3.11"/' "$$HERMES_AGENT_DIR/pyproject.toml"
		pip install -e "$$HERMES_AGENT_DIR"
		mkdir -p $(HOME)/.local/bin
		ln -sf "$$HERMES_AGENT_DIR/cli.py" $(HOME)/.local/bin/hermes
		echo "✓ Hermes Agent installed"
	fi

install-skills:
	@echo "=== Installing skills ==="
	@bash $(SCRIPT_DIR)/install-skills.sh --symlink

install-plugins:
	@echo "=== Installing plugins ==="
	@bash $(SCRIPT_DIR)/install-plugins.sh --symlink

configure-mcp:
	@echo "=== Configuring MCP servers ==="
	@if [ -f "$(HERMES_HOME)/config.yaml" ]; then
		python3 $(SCRIPT_DIR)/configure-mcp.py
	else
		echo "No config.yaml found. Copy template:"
		echo "  cp config.yaml.example $(HERMES_HOME)/config.yaml"
		echo "Then run: make configure-mcp"
	fi

verify:
	@echo "=== Verifying integration ==="
	@bash $(SCRIPT_DIR)/verify-integration.sh --verbose

update-external:
	@echo "=== Updating external dependencies ==="
	@bash $(SCRIPT_DIR)/update-external.sh
