# Qwen3-4B-Instruct-2507 (Q4_K_M) as a weights-only OCI image, mounted into the
# stock llama.cpp server as a Kubernetes image volume -- releases/llama-cpp-chat.yaml.
#
# Weights-only (FROM scratch) rather than baked into a llama.cpp image like
# images/nomic-embed/: at 2.5GB the model dominates the image, and keeping it
# separate means a llama.cpp bump never re-pushes it and vice versa.
#
# Local chat model for the kagent agents while there's no hosted LLM key. 4B
# over the 3B used earlier because the 3B's tool calling was the bottleneck
# (harness-course ADR-0004: 2/14 agentic writes finished).
#
# Built and pushed by .github/workflows/qwen3-4b-image.yaml.

# Only the download runs, on the builder's native platform -- the file is
# platform-agnostic, so both arch variants below share one layer.
FROM --platform=$BUILDPLATFORM curlimages/curl:8.11.0 AS fetch
# curlimages/curl runs as curl_user, which can't write the root-owned WORKDIR.
USER root
ARG HF_REPO=unsloth/Qwen3-4B-Instruct-2507-GGUF
ARG HF_FILE=Qwen3-4B-Instruct-2507-Q4_K_M.gguf
WORKDIR /models
RUN curl -fsSL --retry 5 --retry-delay 3 --retry-connrefused \
      -o /models/model.gguf \
      "https://huggingface.co/${HF_REPO}/resolve/main/${HF_FILE}" \
    && test -s /models/model.gguf

FROM scratch
COPY --from=fetch /models/model.gguf /models/model.gguf
