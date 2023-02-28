using Pkg;
Pkg.activate("..");
Pkg.instantiate();

using WebSockets
import Sockets
import HTTP

const LOCALIP = "0.0.0.0"
const PORT = 1234

mutable struct State
    k::Int
    connected::Set{String}
    mainChannel::Channel{String}
    nextIteration::Threads.Condition
    mutex::ReentrantLock
end

struct Config
    clients::Dict{String,String}
end

lock = SpinLock()
condvar = Condition(lock)


function coroutine(ws, state::State, config::Config)
    try
        @info "Started coroutine for " ws
        id = nothing

        localK = 0

        while isopen(ws)
            data, stillopen = readguarded(ws)
            if !stillopen
                @info "Connection closed by peer"
                break
            end
            data = String(data)

            if id === nothing
                foundId, found = get_id(data)
                if !found
                    stillopen = writeguarded(ws, "No id found")
                    if !stillopen
                        @info "Connection closed by peer"
                        break
                    end
                    @info "Unexpected message"
                    continue
                end

                if !(foundId in keys(config.clients))
                    stillopen = writeguarded(ws, "No client found")
                    if !stillopen
                        @info "Connection closed by peer"
                        break
                    end
                    @info "No client found"
                    continue
                end

                if foundId in state.connected
                    stillopen = writeguarded(ws, "Client already connected")
                    if !stillopen
                        @info "Connection closed by peer"
                        break
                    end
                    @info "Client tried to connect twice"
                    continue
                end

                id = foundId
                lock(state.mutex) do
                    push!(state.connected, id)
                end

                put!(state.mainChannel, id)
            end

            if state.k == 0
                stillopen = writeguarded(ws, config.clients[id])
            end


            lock(state.nextIteration) do
                while state.k == localK
                    wait(state.nextIteration)
                end
            end
            localK = state.k
            stillOpen = writeguarded(ws, "Iteration $state.k")
            if !stillOpen
                @info "Connection closed by peer"
                break
            end
        end
        @info "Will now close " ws

    catch e
        @error "Something went wrong" exception = (e, catch_backtrace())
        error(e)
    end
end


# expect "id:<id>"
function get_id(data::String)
    if startswith(data, "id:")
        return data[4:end], true
    end
    return nothing, false
end

function gatekeeper(_, ws)
    coroutine(ws, state, config)
end

function handle(req)
    @info "Got request: " req.target
    return HTTP.Messages.Response(404, "Not Found")
end

const server = WebSockets.ServerWS(handle, gatekeeper)




config = Config(Dict("1" => "client1", "2" => "client2"))
N_CLIENTS = length(config.clients)
mutex = ReentrantLock()
mainChannel = Channel{String}(N_CLIENTS)
nextIteration = Threads.Condition()
state = State(0, Set{String}(), mainChannel, nextIteration, mutex)


function startController(config::Config, state::State)
    channel = state.mainChannel
    nConnected = 0

    @info "Controller started"

    while true
        msg = take!(channel)
        @info "Got message: " msg
        nConnected += 1

        if nConnected == N_CLIENTS
            @info "All clients connected"
            state.k = 1
            lock(state.nextIteration) do
                @info "Notifying clients"
                notify(state.nextIteration)
            end
            @info "Woke up $nWoken clients"
        end
    end
end

controllerTask = @task startController(config, state)

schedule(controllerTask)

@info "In browser > $LOCALIP:$PORT , F12> console > ws = new WebSocket(\"ws://$LOCALIP:$PORT\") "
WebSockets.with_logger(WebSocketLogger()) do
    WebSockets.serve(server, LOCALIP, PORT)
end