// Extended Pascal example derived from Pegged (Boost Software License 1.0).
module pascal_app;
import epparser;
import npegged.io;
import npegged.storage : Buffer;
import npegged.tohtml;
import core.stdc.stdio : fwrite, fprintf, fflush, stdout, stderr;

private struct TraceState {
    Status status;
}

private void traceRule(string name, size_t pos, bool success, void* user) @nogc nothrow {
    auto state = cast(TraceState*)user;
    if (fprintf(stderr, "%.*s at %zu: %s\n", cast(int)name.length, name.ptr, pos, success
            ? "matched".ptr : "failed".ptr) < 0)
        state.status = Status.ioError;
}

int main(string[] args) @nogc nothrow {
    bool html, tracing;
    string path;
    foreach (argument; args[1 .. $]) {
        if (argument == "--trace")
            tracing = true;
        else if (argument == "--html")
            html = true;
        else if (argument == "--text")
            html = false;
        else if (path.length)
            return 2;
        else
            path = argument;
    }
    if (!path.length)
        return 2;
    auto file = File.open(path);
    Buffer!char input;
    if (file.read(input) != Status.ok)
        return 2;
    ParseContext context;
    TraceState traceState;
    if (tracing) {
        context.trace = &traceRule;
        context.userData = &traceState;
    }
    auto parsed = EP(context, cast(string)input.data);
    auto traceFlushed = fflush(stderr);
    if (!((traceState.status == Status.ok) & (traceFlushed == 0)))
        return 2;
    if (parsed.status != Status.ok) {
        auto diagnostic = parsed.failMsg;
        if (diagnostic.status != Status.ok || fwrite(diagnostic.data.ptr, 1, diagnostic.data.length,
                stderr) != diagnostic.data.length || fflush(stderr) != 0)
            return 2;
        return 1;
    }
    auto text = html ? toHTML(parsed.tree) : parsed.toString;
    if (text.status != Status.ok)
        return 2;
    auto written = fwrite(text.data.ptr, 1, text.data.length, stdout);
    auto flushed = fflush(stdout);
    return ((written == text.data.length) & (flushed == 0)) ? 0 : 2;
}
