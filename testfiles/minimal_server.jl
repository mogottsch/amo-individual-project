import Pkg;
Pkg.activate("..");
Pkg.instantiate();

using WebSockets
import HTTP
import Statistics

const LOCALIP = "0.0.0.0"
const PORT = 1234


struct Config
    clients::Dict{String,String}
end


struct ClientUpdate
    id::String
    value::Float64
end

mutable struct State
    k::Int
    connected::Set{String}
    mainChannel::Channel{ClientUpdate}
    nextIteration::Threads.Condition
    mutex::ReentrantLock
end

function reportClientUpdate(channel::Channel{ClientUpdate}, id::String, value::Float64)
    put!(channel, ClientUpdate(id, value))
end

struct LoggerConfig
    prefix::String
end

function log(config::LoggerConfig, msg)
    return "[$(config.prefix)] $msg"
end

function createLogger(prefix::String)
    return LoggerConfig(prefix)
end

function readWs(ws::WebSockets.WebSocket, logger::LoggerConfig)::Tuple{String,Bool}
    data, stillopen = readguarded(ws)
    if !stillopen
        @info log(logger, "Connection closed by peer")
        return nothing, false
    end
    return String(data), true
end

function writeWs(ws::WebSockets.WebSocket, data::String, logger::LoggerConfig)::Bool
    stillopen = writeguarded(ws, data)
    if !stillopen
        @info log(logger, "Connection closed by peer")
        return false
    end
    return true
end

function initClient(data::String, state::State, config::Config, logger::LoggerConfig)::Tuple{String,String}
    foundId, found = get_id(data)
    if !found
        @info log(logger, "No id found")
        return nothing, "No id found"
    end

    if !(foundId in keys(config.clients))
        @info log(logger, "No client found")
        return nothing, "No client found"
    end


    lock(state.mutex)
    if foundId in state.connected
        @info log(logger, "Client already connected")
        unlock(state.mutex)
        return nothing, "Client already connected"
    end
    id = foundId
    push!(state.connected, id)
    unlock(state.mutex)

    reportClientUpdate(state.mainChannel, id, 0.0)
    return id, "Connected"
end

function coroutine(ws::WebSockets.WebSocket, state::State, config::Config)
    try
        logger = createLogger("COROUTINE")
        @info log(logger, "Starting coroutine")

        id = nothing
        localK = 0

        while isopen(ws)
            data, stillopen = readWs(ws, logger)
            if !stillopen
                break
            end


            ## registration in iteration 0
            if id === nothing
                id, msg = initClient(data, state, config, logger)

                stillopen = writeguarded(ws, msg)
                if !stillopen
                    @info log(logger, "Connection closed by peer")
                    break
                end

                if id === nothing
                    continue
                end

                logger = createLogger("COROUTINE - $id")
            end

            ## end of registration


            ## actions in iteration k
            if state.k > 0
                value = nothing
                try
                    value = parse(Float64, data)
                    reportClientUpdate(state.mainChannel, id, value)
                catch
                    @info log(logger, "Could not parse value")

                    stillopen = writeWs(ws, "Could not parse value", logger)
                    if !stillopen
                        break
                    end

                    continue
                end
            end
            ## end of actions


            newMean = nothing
            ## wait for next iteration
            lock(state.nextIteration) do
                while state.k == localK
                    newMean = wait(state.nextIteration)
                    @info log(logger, "Woke up")
                end
            end
            ## end of wait

            localK = state.k

            ## answer to client
            stillOpen = writeWs(ws, "mean:$newMean", logger)
            if !stillOpen
                @info log(logger, "Connection closed by peer")
                break
            end
            ## end of answer
        end
        @info log(logger, "Coroutine finished")

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
mainChannel = Channel{ClientUpdate}(N_CLIENTS)
nextIteration = Threads.Condition()
state = State(0, Set{String}(), mainChannel, nextIteration, mutex)


function startController(config::Config, state::State)
    logger = createLogger("CONTROLLER")
    channel = state.mainChannel
    connected = state.connected

    localK = 0
    currentMean = 0.0
    ϵ = 0.1

    @info log(logger, "Controller started")

    recValues = Float64[]

    while true
        clientUpdate = take!(channel)
        @info log(logger, "[CONTROLLER] Got message: $clientUpdate")

        if localK == 0
            if length(connected) == N_CLIENTS
                @info log(logger, "[CONTROLLER] All clients connected")
                localK = 1
                lock(state.mutex) do
                    state.k = localK
                end
                state.k = 1
                nWoken = nothing
                lock(state.nextIteration) do
                    @info log(logger, "[CONTROLLER] Notifying clients")
                    nWoken = notify(state.nextIteration, currentMean)
                end
                @info log(logger, "Woke up $nWoken clients")
            end
            continue
        end

        push!(recValues, clientUpdate.value)

        if length(recValues) == N_CLIENTS
            @info log(logger, "[CONTROLLER] All clients answered")

            newMean = Statistics.mean(recValues)
            std = Statistics.std(recValues)
            recValues = Float64[]

            @info log(logger, "[CONTROLLER] Std: $std")
            if std < ϵ
                @info "[CONTROLLER] Converged"
                break
            end

            currentMean = newMean
            @info log(logger, "[CONTROLLER] New mean: $currentMean")

            localK += 1
            lock(state.mutex) do
                state.k = localK
            end
            nWoken = nothing
            lock(state.nextIteration) do
                @info log(logger, "[CONTROLLER] Notifying clients")
                nWoken = notify(state.nextIteration, currentMean)
            end
            @info log(logger, "[CONTROLLER] Woke up $nWoken clients")
        end

    end
    @info log(logger, "[CONTROLLER] Controller finished")
end

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
        break
    end
    sleep(1)
end
