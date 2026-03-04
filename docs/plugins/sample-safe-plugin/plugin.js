let state = {
  loadedAt: null,
  unloadCount: 0,
};

export async function load(context) {
  state.loadedAt = new Date().toISOString();
  return {
    status: "loaded",
    pluginId: context?.pluginId ?? "sample.safe.tools",
    loadedAt: state.loadedAt,
  };
}

export async function unload() {
  state.unloadCount += 1;
  return {
    status: "unloaded",
    unloadCount: state.unloadCount,
  };
}

export async function handle(request) {
  if (request?.tool === "sample.echo.safe") {
    const raw = String(request?.payload?.message ?? "");
    const sanitized = raw.replace(/\s+/g, " ").trim().slice(0, 240);
    return {
      output: sanitized,
      metadata: {
        sanitized: "true",
        source: "sample.safe.tools",
      },
    };
  }

  if (request?.tool === "sample.web.ping") {
    return {
      output: "pong",
      metadata: {
        source: "sample.safe.tools",
        loadedAt: state.loadedAt ?? "unknown",
      },
    };
  }

  throw new Error(`Tool non esposto: ${request?.tool ?? "unknown"}`);
}
