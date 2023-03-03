import Pkg;
Pkg.activate(".");
Pkg.instantiate();
import WebSockets

include("coroutine.jl")
include("controller.jl")
include("config.jl")


function gatekeeper(_, ws)
    coroutineWrapper(ws, state, config)
end

function handle(req)
    @info "Got request: " req.target
    return HTTP.Messages.Response(404, "Not Found")
end

const server = WebSockets.ServerWS(handle, gatekeeper)

config = Config(2)
N_CLIENTS = length(config.clients)
mutex = ReentrantLock()
mainChannel = Channel{ClientUpdate}(N_CLIENTS)
nextIteration = Threads.Condition()
state = State(0, Set{String}(), mainChannel, nextIteration, mutex)

controllerTask = @task startController(config, state)

serverTask = @task WebSockets.with_logger(WebSocketLogger()) do
    @info "In browser > $LOCALIP:$PORT , F12> console > ws = new WebSocket(\"ws://$LOCALIP:$PORT\") "
    WebSockets.serve(server, LOCALIP, PORT)
end


schedule(controllerTask)
schedule(serverTask)

# check if task crashed
while true
    if istaskfailed(serverTask)
        @error "Server crashed" exception = (serverTask.exception, serverTask.backtrace)
        break
    end
    if istaskfailed(controllerTask)
        @error "Controller crashed" exception = (controllerTask.exception, controllerTask.backtrace)
        break
    end

    if istaskdone(controllerTask)
        @info "Controller finished - stopping server"
        WebSockets.close(server)
        exit(0)
    end
    sleep(1)
end
