"""Reference: Working Modal app for Gemma 4 12B GGUF with llama-cpp-python.
Deploys to Modal with a T4 GPU, persistent model volume, and OpenAI-compatible endpoint.

Deploy:  python deploy_gemma.py
Test:    curl $WEB_URL/v1/chat/completions -d '{"model":"gemma-4b","messages":[{"role":"user","content":"hello"}]}'
"""

import modal

image = (
    modal.Image.debian_slim()
    .apt_install("build-essential", "curl")
    .pip_install("llama-cpp-python", "fastapi[standard]")
)

volume = modal.Volume.from_name("gemma-models", create_if_missing=True)
app = modal.App("gemma4-12b")


def _get_llm():
    """Lazy-load Llama singleton with GPU offload."""
    import os
    from llama_cpp import Llama
    model_path = "/models/gemma-4-12b-it-Q4_K_M.gguf"
    if not os.path.exists(model_path):
        import urllib.request
        url = "https://huggingface.co/unsloth/gemma-4-12b-it-GGUF/resolve/main/gemma-4-12b-it-Q4_K_M.gguf"
        print(f"Downloading {url} ...")
        urllib.request.urlretrieve(url, model_path)
        print("Download complete.")
    return Llama(model_path=model_path, n_ctx=8192, n_gpu_layers=-1, verbose=False)


@app.function(gpu="t4", image=image, volumes={"/models": volume}, timeout=600)
def generate(prompt: str, max_tokens: int = 1024, temperature: float = 0.7) -> str:
    """Simple prompt → response (used by connector scripts)."""
    llm = _get_llm()
    result = llm.create_chat_completion(
        messages=[{"role": "user", "content": prompt}],
        max_tokens=max_tokens, temperature=temperature,
    )
    return result["choices"][0]["message"]["content"]


@app.function(
    gpu="t4", image=image, volumes={"/models": volume},
    timeout=600, scaledown_window=300, allow_concurrent_inputs=10,
)
@modal.fastapi_endpoint(method="POST", label="gemma4-chat")
def chat_completions(data: dict):
    """OpenAI-compatible /v1/chat/completions."""
    llm = _get_llm()
    messages = [{"role": m["role"], "content": m["content"]} for m in data.get("messages", [])]
    result = llm.create_chat_completion(
        messages=messages,
        max_tokens=data.get("max_tokens", 1024),
        temperature=data.get("temperature", 0.7),
    )
    return {"id": result["id"], "object": "chat.completion",
            "created": result["created"], "model": "gemma-4-12b",
            "choices": result["choices"], "usage": result.get("usage", {})}
