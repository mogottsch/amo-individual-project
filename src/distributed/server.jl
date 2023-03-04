import WebSockets

include("../ieee_parser.jl")
include("config.jl")
include("controller.jl")
include("coroutine.jl")

const LOCALIP = "0.0.0.0" # listen on all interfaces
const PORT = 1234

function startFor(file::String)
    @info "Initializing data"
    config, state, data = setup(file)
    serverTask, controllerTask, closeServer = setupTasks(config, state, data)

    schedule(controllerTask)
    schedule(serverTask)

    @info "Handing over to watchdog"
    result = watchdog(serverTask, controllerTask, closeServer)
    return result
end

function setup(file::String)::Tuple{Config,State,Data}
    busses, lines = read_IEEE_common_data_format(file)
    # busses, lines = parsed_busses, parsed_lines

    nClients = length(busses) + length(lines)
    data = createData(busses, lines)
    ϵ = 0.0001
    ρ = 0.1
    config = Config(nClients, ϵ, ρ)
    # config = Config(2, ϵ, ρ)
    state = initState(nClients)

    return config, state, data
end

function setupTasks(config::Config, state::State, data::Data)
    function gatekeeper(_, ws)
        coroutineWrapper(ws, state, config, data)
    end

    server = WebSockets.ServerWS(handle, gatekeeper)
    controllerTask = @task startController(config, state, data)

    serverTask = @task WebSockets.with_logger(WebSockets.WebSocketLogger()) do
        @info "Serving > $LOCALIP:$PORT"
        WebSockets.serve(server, LOCALIP, PORT)
    end

    function closeServer()
        WebSockets.close(server)
    end

    return serverTask, controllerTask, closeServer
end

function handle(req)
    @info "Got request: " req.target
    return HTTP.Messages.Response(404, "Not Found")
end

function watchdog(serverTask::Task, controllerTask::Task, closeServer::Function)
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
            result = fetch(controllerTask)
            @info "Controller finished - stopping server"
            closeServer()
            return result
        end
        sleep(1)
    end
end
