"""Deploy Gemma 4 Modal app from Termux/PRoot using Python API (bypasses broken CLI).
"""
import importlib.util, sys

sys.path.insert(0, "/root")
spec = importlib.util.spec_from_file_location("gemma4_modal", "/root/gemma4-modal.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

print("Deploying gemma4-12b...")
mod.app.deploy(name="gemma4-12b")
print("✅ Done! Dashboard: https://modal.com/apps/gemma4-12b")
