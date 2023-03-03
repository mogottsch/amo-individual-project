import WebSockets
import JSON

include("logger.jl")
include("controller.jl")
include("config.jl")
include("utils.jl")
include("ws.jl")

function coroutineWrapper(ws::WebSockets.WebSocket, state::State, config::Config, data::Data)
    try
        coroutine(ws, state, config, data)
    catch e
        @error "Something went wrong" exception = (e, catch_backtrace()) # captures full stacktrace
        error(e)
    end
end

function coroutine(ws::WebSockets.WebSocket, state::State, config::Config, data::Data)
    logger = createLogger("COROUTINE")
    @info log(logger, "Starting coroutine")

    id = nothing
    localK = 0

    while isopen(ws)
        message, stillopen = readWs(ws, logger)
        if !stillopen
            break
        end


        ## registration in iteration 0
        if id === nothing
            id, answer = initClient(message, state, data, logger)

            stillopen = writeWs(ws, answer, logger)

            if id === nothing
                continue
            end

            logger = createLogger("COROUTINE-$id")
        end

        ## end of registration


        ## actions in iteration k
        if state.k > 0
            try
                clientUpdate = parseClientUpdate(message, id)
                reportClientUpdate(state.mainChannel, clientUpdate)
            catch e
                @warn log(logger, "Could not parse value") exception = (e, catch_backtrace())
                stillopen = writeWs(ws, "Could not parse value", logger)
                if !stillopen
                    break
                end

                continue
            end
        end
        ## end of actions


        δs = Dict{Symbol,Float64}()
        λ_δs = Dict{Symbol,Float64}()
        ## wait for next iteration
        lock(state.nextIteration) do
            while state.k == localK
                δs, λ_δs = wait(state.nextIteration)
                @info log(logger, "Woke up")
                δs = getRelevantδs(δs, data.busses, id)
                λ_δs = getRelevantλ_δs(λ_δs, id)
            end
        end
        ## end of wait

        localK = state.k

        ## answer to client
        answer = Dict(
            "k" => localK,
            "deltas" => δs,
            "lambda_deltas" => λ_δs,
        )
        stillOpen = writeWs(ws, JSON.json(answer), logger)
        if !stillOpen
            break
        end
        ## end of answer
    end
    @info log(logger, "Coroutine finished")
end

function getRelevantδs(
    δs::Dict{Symbol,Float64},
    busses::Dict{Symbol,Bus},
    id::String,
)::Dict{Symbol,Float64}
    isBus = checkIsBus(id)

    if !isBus
        return Dict(
            Symbol(id) => δs[Symbol(id)]
        )
    end
    bus = busses[Symbol(id)]

    lines = union(bus.incoming, bus.outgoing)
    @assert length(lines) > 0

    relevantδs = Dict{Symbol,Float64}()
    for line in lines
        relevantδs[line] = δs[line]
    end
    @assert length(relevantδs) == length(lines)
    return relevantδs
end

function getRelevantλ_δs(λ_δs::Dict{Symbol,Dict{Symbol,Float64}}, id::String)::Dict{Symbol,Float64}
    return λ_δs[Symbol(id)]
end

function initClient(message::String, state::State, data::Data, logger::LoggerConfig)
    foundId, found = get_id(message)
    if !found
        m = "No id found: '$message'"
        @warn log(logger, m)
        return nothing, m
    end

    if !(foundId in data.clients)
        m = "No client found: '$foundId'"
        @warn log(logger, m)
        return nothing, m
    end


    lock(state.mutex)
    if foundId in state.connected
        @warn log(logger, "Client already connected")
        unlock(state.mutex)
        return nothing, "Client already connected"
    end
    id = foundId
    push!(state.connected, id)
    unlock(state.mutex)

    reportClientUpdate(state.mainChannel, createEmptyClientUpdate(id))

    isBus = checkIsBus(id)
    object = isBus ? data.busses[Symbol(id)] : data.lines[Symbol(id)]

    answer = JSON.json(toJSON(object))
    return id, answer
end

function parseClientUpdate(message::String, id::String)::ClientUpdate
    clientUpdateDict = JSON.parse(message)
    δs = clientUpdateDict["deltas"]
    δs = Dict{Symbol,Float64}(Symbol(k) => v for (k, v) in δs)
    objective = clientUpdateDict["objective"]
    P = get(clientUpdateDict, "P", nothing)
    type = P === nothing ? :line : :bus
    return ClientUpdate(id, type, δs, P, objective)
end

function createEmptyClientUpdate(id::String)::ClientUpdate
    return ClientUpdate(id, :unknown, Dict{Symbol,Float64}(), nothing, 0.0)
end

# expect "id:<id>"
function get_id(data::String)
    if startswith(data, "id:")
        return data[4:end], true
    end
    return nothing, false
end

function reportClientUpdate(channel::Channel{ClientUpdate}, clientUpdate::ClientUpdate)
    put!(channel, clientUpdate)
end
