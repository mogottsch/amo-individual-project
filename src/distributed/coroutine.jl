import WebSockets

include("logger.jl")
include("controller.jl")

include("config.jl")

function coroutineWrapper(ws::WebSockets.WebSocket, state::State, config::Config)
    try
        coroutine(ws, state, config)
    catch e
        @error "Something went wrong" exception = (e, catch_backtrace()) # captures full stacktrace
        error(e)
    end
end

function coroutine(ws::WebSockets.WebSocket, state::State, config::Config)
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




# expect "id:<id>"
function get_id(data::String)
    if startswith(data, "id:")
        return data[4:end], true
    end
    return nothing, false
end




function readWs(ws::WebSockets.WebSocket, logger::LoggerConfig)::Tuple{String,Bool}
    data, stillopen = readguarded(ws)
    if !stillopen
        @info log(logger, "Connection closed by peer")
        return "", false
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


function reportClientUpdate(channel::Channel{ClientUpdate}, id::String, value::Float64)
    put!(channel, ClientUpdate(id, value))
end
