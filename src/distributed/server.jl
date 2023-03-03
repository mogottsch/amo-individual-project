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
    watchdog(serverTask, controllerTask, closeServer)
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
            @info "Controller finished - stopping server"
            closeServer()
            exit(0)
        end
        sleep(1)
    end
end


# ### SIMPLE 
# busses = Dict(
#     :B1 => Dict(
#         :cost => 12,
#         :P_min => 0,
#         :P_max => 250,
#         :load => 160,
#         :incoming => [:L3],
#         :outgoing => [:L1],
#     ),
#     :B2 => Dict(
#         :cost => 20,
#         :P_min => 0,
#         :P_max => 300,
#         :load => 100,
#         :incoming => [:L1],
#         :outgoing => [:L2],
#     ),
#     :B3 => Dict(
#         :cost => 17,
#         :P_min => 0,
#         :P_max => 350,
#         :load => 50,
#         :incoming => [:L2],
#         :outgoing => [:L3],
#     ),
# )
#
# lines = Dict(
#     :L1 => Dict(
#         :from => :B1,
#         :to => :B2,
#         :capacity => 100,
#     ),
#     :L2 => Dict(
#         :from => :B2,
#         :to => :B3,
#         :capacity => 100,
#     ),
#     :L3 => Dict(
#         :from => :B3,
#         :to => :B1,
#         :capacity => 100,
#     ),
# )
# parsed_busses = Dict{Symbol,Bus}()
# for (id, bus) in busses
#     parsed_busses[id] = Bus(id, bus[:cost], bus[:P_min], bus[:P_max], bus[:load], Set(bus[:incoming]), Set(bus[:outgoing]))
# end
#
# parsed_lines = Dict{Symbol,Line}()
# for (id, line) in lines
#     parsed_lines[id] = Line(id, line[:from], line[:to], line[:capacity])
# end
# ### END SIMPLE
