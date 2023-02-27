using Pkg;
Pkg.activate("..");
Pkg.instantiate();

using WebSockets
import Sockets

const LOCALIP = string(Sockets.getipaddr())
const PORT = 1234

function coroutine(ws)
    @info "Started coroutine for " ws
    while isopen(ws)
        data, = readguarded(ws)
        s = String(data)
        if s == ""
            writeguarded(ws, "Goodbye!")
            break
        end
        @info "Received: $s"
        writeguarded(ws, "Hello! Send empty message to exit, or just leave.")
    end
    @info "Will now close " ws
end

function gatekeeper(req, ws)
    orig = WebSockets.origin(req)
    @info "\nOrigin: $orig   Target: $(req.target)   subprotocol: $(subprotocol(req))"
    if occursin(LOCALIP, orig)
        coroutine(ws)
    elseif orig == ""
        @info "Non-browser clients don't send Origin. We liberally accept the update request in this case:" ws
        coroutine(ws)
    else
        @warn "Inacceptable request"
    end
end

handle(req) = println("Got request: ", req.target)

const server = WebSockets.ServerWS(handle, gatekeeper)

@info "In browser > $LOCALIP:$PORT , F12> console > ws = new WebSocket(\"ws://$LOCALIP:$PORT\") "
WebSockets.with_logger(WebSocketLogger()) do
    WebSockets.serve(server, LOCALIP, PORT)
end