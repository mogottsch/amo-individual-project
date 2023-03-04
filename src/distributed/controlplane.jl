include("../common.jl")
include("./client.jl")
include("./server.jl")
include("../ieee_parser.jl")

function startControlPlane(
    filepath::String
)

    busses, lines = read_IEEE_common_data_format(filepath)
    ids = Set()
    for (id, bus) in busses
        push!(ids, id)
    end
    for (id, line) in lines
        push!(ids, id)
    end
    @info "Done collecting ids of length $(length(ids))"


    serverTask = @task startFor(filepath)
    clientTasks = Dict{Symbol,Task}()
    for id in ids
        clientTasks[id] = @task startClient(String(id))
    end

    schedule(serverTask)
    @info "Waiting for server to start"
    sleep(5)
    @info "Starting clients"
    for (id, task) in clientTasks
        schedule(task)
    end
    @info "Started $(length(clientTasks)) clients"

    while true
        if istaskfailed(serverTask)
            @error fetch(serverTask)
            break
        end
        for (id, task) in clientTasks
            if istaskfailed(task)
                @error fetch(task)
                break
            end

            if istaskdone(task)
                @info "Client $id done"
                break
            end
        end
        if istaskdone(serverTask)
            @info "Server done"
            result = fetch(serverTask)
            return result
            break
        end
        yield()
    end
end
